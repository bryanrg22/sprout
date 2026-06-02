//
//  LocationService.swift
//  Victoria
//
//  A deliberately tiny CoreLocation wrapper for Sprout.
//
//  SCOPE — permission only (for now):
//  This service's *only* job today is to ask the user for "When In Use" location
//  permission and to expose the current authorization status so SwiftUI views can
//  react to it. It does NOT start location updates and never reads coordinates.
//
//  WHY WE ASK AT ALL:
//  A future "nearby healthy-food suggestions" feature wants to point Sprout at
//  the user's surroundings (e.g. salad spots / grocery stores close by). That
//  feature will add the actual coordinate-fetching on top of this class — the
//  shape below is built so that's a small, additive change rather than a rewrite.
//
//  INTEGRATOR NOTE — Info.plist:
//  iOS will silently refuse to prompt unless the Info.plist contains
//      NSLocationWhenInUseUsageDescription
//  with a human-friendly reason string. That key is being added separately; if
//  the prompt never appears on device, that missing string is the first thing to
//  check. Without it, `requestWhenInUse()` no-ops rather than crashing.
//

import CoreLocation
import Foundation
import Observation

/// Permission-only CoreLocation wrapper. See file header for scope and the
/// Info.plist requirement. Observe `status` / `isAuthorized` from SwiftUI to
/// drive UI; call `requestWhenInUse()` to (politely) ask once.
///
/// Threading: the whole class is pinned to the main actor. CLLocationManager is
/// happy to be created and messaged from the main thread, and pinning here means
/// every mutation of the `@Observable` `status` property is main-actor isolated —
/// no data races, and SwiftUI observation just works.
///
/// The one subtlety is the delegate callback: `CLLocationManagerDelegate`'s
/// requirements are `nonisolated`, so a `@MainActor` method can't satisfy them
/// directly (Swift 6 rightly warns about a possible cross-actor data race). We
/// handle that in `locationManagerDidChangeAuthorization` below — see the comment
/// there — rather than by weakening the isolation of the whole class.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    /// Shared instance. One location manager for the whole app is plenty; there's
    /// no reason to juggle several permission owners.
    static let shared = LocationService()

    // MARK: Observable state

    /// The current authorization status, mirrored from the system. Seeded from
    /// the manager at init and kept in sync via the delegate callback below.
    /// `private(set)` so only the system (through us) can change it.
    private(set) var status: CLAuthorizationStatus

    // MARK: Derived state

    /// `true` once we hold a usable grant ("when in use" or the broader "always").
    /// This is the flag most UI should branch on.
    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// `true` once the user has made *any* choice (granted or denied) — i.e. we're
    /// no longer in the initial `.notDetermined` limbo. Useful for deciding whether
    /// it's still worth showing a "Enable location" call-to-action.
    var isDetermined: Bool {
        status != .notDetermined
    }

    // MARK: Internals

    /// The one and only manager. Kept private so callers go through this service's
    /// small, intentional surface rather than poking CoreLocation directly.
    private let manager = CLLocationManager()

    /// In-flight continuations for `currentLocation()`, keyed by a per-call id. A one-shot
    /// `requestLocation()` resolves via the delegate on a later runloop turn, so we park
    /// each awaiter here and resume it when the fix (or failure) arrives. Keyed (not a bare
    /// array) so a per-call timeout can resolve exactly its own awaiter without disturbing
    /// the others, and so any resolution path is idempotent — `takeWaiters()` /
    /// `takeWaiter(_:)` remove before resuming, so a continuation is never resumed twice
    /// (which would trap). Several callers can await at once; the shared fix resolves all.
    private var locationWaiters: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]

    // MARK: Lifecycle

    private override init() {
        // Read the starting status *before* we touch `super`/the delegate, so the
        // stored property is fully initialized.
        status = manager.authorizationStatus
        super.init()

        // From here on, the system tells us about authorization changes.
        manager.delegate = self
    }

    // MARK: Public API

    /// Politely request "When In Use" authorization — but only if the user hasn't
    /// already answered. Once a decision exists (granted *or* denied), iOS won't
    /// re-prompt anyway, so we don't bother and instead leave it to the user to
    /// change their mind in Settings. Safe to call repeatedly / on every appear.
    func requestWhenInUse() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Fetch the device's current location ONCE (async), or `nil` if we can't.
    ///
    /// This is the additive coordinate-fetch the file header anticipated, kept narrow:
    /// it returns a single fix and stops — no continuous updates, no battery cost beyond
    /// one fix. It's used to seed the "nearby healthy spots" search; that whole feature
    /// is optional, so returning `nil` (no permission, location services off, or a
    /// transient error) must degrade gracefully — the caller simply omits nearby picks.
    ///
    /// Behavior:
    /// - Not authorized → returns `nil` immediately (we do NOT prompt here; permission
    ///   is requested separately/up front via `requestWhenInUse()`).
    /// - Authorized → calls `requestLocation()` and awaits the one-shot delegate callback.
    ///   `requestLocation` already delivers a single fix and auto-cancels, so there's no
    ///   updates session to tear down.
    /// - A `timeout` guards against the rare case where no callback arrives (some
    ///   simulators never deliver a fix): the awaiter resolves to `nil` after the timeout
    ///   so a caller — e.g. the suggestions loader — can't wedge on a stuck request.
    ///
    /// Concurrency: `@MainActor`, so reads/writes of `locationWaiters` are isolated; the
    /// delegate callbacks re-enter the main actor via `MainActor.assumeIsolated` (same as
    /// the authorization callback) and drain the waiters. Continuations are `Never`-typed
    /// (we surface "couldn't get it" as `nil`, never as a thrown error).
    func currentLocation(timeout: Duration = .seconds(8)) async -> CLLocation? {
        guard isAuthorized else { return nil }
        let id = UUID()

        // A detached timeout that resolves *this* awaiter if the delegate is slow/silent.
        // It's safe if the delegate already fired: `takeWaiter` returns nil and this no-ops.
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            takeWaiter(id)?.resume(returning: nil)
        }

        let location = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            let wasEmpty = locationWaiters.isEmpty
            locationWaiters[id] = cont
            // Only kick off a request for the first awaiter; any others ride along on the
            // same in-flight fix and are resumed together by the delegate.
            if wasEmpty { manager.requestLocation() }
        }
        timeoutTask.cancel()   // delegate (or our own timeout) already resolved us
        return location
    }

    /// Atomically remove and return the waiter for `id` (nil if already resolved). The
    /// remove-before-resume guarantees a continuation is resumed at most once.
    private func takeWaiter(_ id: UUID) -> CheckedContinuation<CLLocation?, Never>? {
        locationWaiters.removeValue(forKey: id)
    }

    /// Atomically take ALL parked waiters (clearing the map) for the delegate to resume
    /// with a single shared result. Remove-before-resume keeps every resumption single-shot.
    private func takeWaiters() -> [CheckedContinuation<CLLocation?, Never>] {
        let conts = Array(locationWaiters.values)
        locationWaiters.removeAll()
        return conts
    }

    /// Resume every parked `currentLocation()` awaiter with `result`.
    /// Main-actor isolated (only ever called from the assumed-isolated delegate bodies).
    private func resumeLocationWaiters(with result: CLLocation?) {
        for cont in takeWaiters() { cont.resume(returning: result) }
    }

    // MARK: CLLocationManagerDelegate

    /// Fired by CoreLocation whenever authorization changes (including shortly
    /// after init, and after the user responds to the prompt). We just re-read the
    /// canonical value and store it.
    ///
    /// Isolation: the method is `nonisolated` to satisfy the protocol's
    /// `nonisolated` requirement, then we synchronously re-enter the main actor via
    /// `MainActor.assumeIsolated`. That's safe and correct here because we created
    /// and messaged the manager on the main thread and never gave it a private
    /// dispatch queue, so CoreLocation delivers this callback on the main runloop —
    /// the assumption always holds. We use `assumeIsolated` (not `Task { @MainActor
    /// in }`) deliberately: it's synchronous, so there's no reordering or one-frame
    /// delay, and it traps loudly if the threading assumption is ever violated
    /// instead of hiding the bug.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            status = manager.authorizationStatus
        }
    }

    /// One-shot fix delivered for `requestLocation()`. We resume any parked
    /// `currentLocation()` awaiters with the most-recent (last) location — CoreLocation
    /// appends the freshest fix at the end of the array.
    ///
    /// Isolation: same reasoning as `locationManagerDidChangeAuthorization` — we created
    /// and messaged the manager on the main thread with no private dispatch queue, so the
    /// callback arrives on the main runloop and `assumeIsolated` always holds.
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            resumeLocationWaiters(with: locations.last)
        }
    }

    /// `requestLocation()` failed (services off, transient error, etc.). We don't surface
    /// the error — nearby is optional — so awaiters simply resolve to `nil` and the UI
    /// quietly omits nearby picks.
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        MainActor.assumeIsolated {
            resumeLocationWaiters(with: nil)
        }
    }
}
