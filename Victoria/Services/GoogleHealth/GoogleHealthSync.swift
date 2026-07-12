import Foundation
import SwiftData

/// Pulls the Fitbit Air's data straight from the Google Health API and lands it in the
/// SAME SwiftData rows the HealthKit path maintains — `SleepEntry`, `VitalsEntry`,
/// `DetectedWorkout` — via the same pure merge functions. Everything downstream
/// (tracker card, sleep charts, recovery signal, Vita's context, the daily brief)
/// works unchanged regardless of which pipe delivered the data.
///
/// Ordering rule: RootView runs this AFTER the HealthKit imports, so on any day both
/// sources report, the direct Google numbers (richer stages, Fitbit's own daily RHR/HRV)
/// win the per-day upsert.
enum GoogleHealthSync {

    /// True when Bryan has completed the Google OAuth connect in Settings.
    @MainActor
    static var isConnected: Bool { GoogleHealthAuth.shared.isConnected }

    /// Last successful sync, for the Settings status row.
    private static let lastSyncKey = "googleHealth.lastSyncAt"
    static var lastSyncAt: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// Re-entry guard: at cold launch BOTH RootView's `.task` and the scenePhase
    /// `.active` handler fire, and a Settings "Sync now" can overlap either. Two
    /// concurrent passes would each snapshot `existing` rows before the other's
    /// inserts — the classic duplicate-row race — so the second caller just skips.
    @MainActor
    private static var isRefreshing = false

    /// Fetch + merge the last `days` days. Reads the CURRENT rows straight from the
    /// ModelContext (never a caller's possibly-stale snapshot — the HealthKit imports
    /// may have inserted rows moments earlier in the same task). Each of the three
    /// streams fails soft and independently — one bad endpoint never blocks the
    /// others. Returns a short summary for the Settings "Sync now" status line.
    @MainActor
    @discardableResult
    static func refresh(days: Int, into context: ModelContext) async -> String {
        guard isConnected else { return "Not connected" }
        guard !isRefreshing else { return "Sync already running" }
        isRefreshing = true
        defer { isRefreshing = false }

        var parts: [String] = []
        var failures: [String] = []

        do {
            let perNight = try await GoogleHealthClient.fetchDailySleep(days: days)
            let existing = (try? context.fetch(FetchDescriptor<SleepEntry>())) ?? []
            let changed = HealthKitService.mergeDailySleep(perNight, into: context,
                                                           existing: existing)
            parts.append("\(perNight.count) nights (\(changed) updated)")
        } catch {
            failures.append("sleep: \(error.localizedDescription)")
        }

        do {
            let perDay = try await GoogleHealthClient.fetchDailyVitals(days: days)
            let existing = (try? context.fetch(FetchDescriptor<VitalsEntry>())) ?? []
            let overlaid = overlayVitals(perDay, onto: existing)
            let changed = HealthKitService.mergeDailyVitals(overlaid, into: context,
                                                            existing: existing)
            parts.append("\(perDay.count) days of vitals (\(changed) updated)")
        } catch {
            failures.append("vitals: \(error.localizedDescription)")
        }

        do {
            let found = try await GoogleHealthClient.fetchWorkouts(days: days)
            let existing = (try? context.fetch(FetchDescriptor<DetectedWorkout>())) ?? []
            let fresh = dedupAgainstExisting(found, existing: existing)
            let added = HealthKitService.mergeDetectedWorkouts(fresh, into: context,
                                                               existing: existing)
            parts.append("\(found.count) workouts (\(added) new)")
        } catch {
            failures.append("workouts: \(error.localizedDescription)")
        }

        let summary = (parts + failures).joined(separator: ", ")
        Diagnostics.shared.log("google health sync (\(days)d): \(summary)",
                               failures.isEmpty ? .sync : .error)
        if !parts.isEmpty { lastSyncAt = .now }
        return failures.isEmpty ? "Synced: \(summary)" : "Partly synced — \(summary)"
    }

    /// "Google wins, but 0 never beats a real reading": mergeDailyVitals overwrites
    /// BOTH halves of a day, and Google legitimately sends half-days (an HRV row
    /// before the RHR row lands). Backfill each missing half from the existing row
    /// so a partial Google day can't wipe a value another source already delivered.
    /// Pure and unit-tested.
    nonisolated static func overlayVitals(_ google: [Date: (rhr: Double, hrv: Double)],
                                          onto existing: [VitalsEntry],
                                          calendar: Calendar = .current)
        -> [Date: (rhr: Double, hrv: Double)] {
        var out = google
        for (day, v) in google where v.rhr == 0 || v.hrv == 0 {
            guard let row = existing.first(where: { calendar.isDate($0.date, inSameDayAs: day) })
            else { continue }
            out[day] = (rhr: v.rhr > 0 ? v.rhr : row.restingHeartRate,
                        hrv: v.hrv > 0 ? v.hrv : row.hrvMs)
        }
        return out
    }

    /// Cross-source workout dedup: if a bridge app is ALSO feeding the same Fitbit
    /// workout through Apple Health, the two copies have different IDs but describe one
    /// physical session. A Google workout is dropped when a non-Google row already
    /// starts within ±20 minutes with a duration within 40% — that's the same session
    /// seen through two pipes, not a second workout. Pure and unit-tested.
    nonisolated static func dedupAgainstExisting(_ found: [HealthKitService.ImportableWorkout],
                                                 existing: [DetectedWorkout])
        -> [HealthKitService.ImportableWorkout] {
        let foreign = existing.filter { !$0.healthKitUUID.hasPrefix("ghealth:") }
        guard !foreign.isEmpty else { return found }
        return found.filter { candidate in
            !foreign.contains { row in
                abs(row.date.timeIntervalSince(candidate.date)) <= 20 * 60
                    && abs(row.durationMinutes - candidate.durationMinutes)
                        <= max(5, Int(Double(max(row.durationMinutes, candidate.durationMinutes)) * 0.4))
            }
        }
    }
}
