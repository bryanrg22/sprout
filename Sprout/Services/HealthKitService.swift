//
//  HealthKitService.swift
//  Sprout
//
//  Wraps HKHealthStore for body-mass (weight) sync.
//
//  INTEGRATOR NOTE: For this to work on a real device you must enable the
//  HealthKit capability / entitlement. With XcodeGen, add to project.yml under
//  the Sprout target, e.g.:
//
//      entitlements:
//        path: Sprout/Sprout.entitlements
//        properties:
//          com.apple.developer.healthkit: true
//          com.apple.developer.healthkit.access: []
//      capabilities:
//        HealthKit: { enabled: true }   # or add via Signing & Capabilities in Xcode
//
//  The NSHealthShareUsageDescription / NSHealthUpdateUsageDescription strings
//  already exist in the Info.plist properties. Do NOT rely on this file alone —
//  without the entitlement, authorization will simply fail and every method
//  below no-ops gracefully (it will NOT crash).
//

import Foundation
import HealthKit
import SwiftData

/// Errors surfaced by `HealthKitService`. These are friendly, user-presentable.
enum HealthKitError: LocalizedError {
    case unavailable
    case bodyMassTypeUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health isn't available on this device."
        case .bodyMassTypeUnavailable:
            return "The Weight data type isn't available on this device."
        }
    }
}

/// A thin, defensive wrapper around HealthKit for reading/writing body mass.
///
/// Everything is written so the app compiles and runs even without the
/// HealthKit entitlement: when Health is unavailable or unauthorized, calls
/// either throw a friendly error or no-op rather than crash.
final class HealthKitService {

    /// Shared instance for convenience; HKHealthStore is intended to be long-lived.
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// Whether HealthKit data is available on this device at all
    /// (false on iPad and some Simulator configurations).
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The body-mass quantity type, or nil if unavailable on this platform.
    private var bodyMassType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

    /// A stable namespace used to build per-sample sync identifiers so that
    /// re-saving the same logical weigh-in updates instead of duplicating.
    private static let syncIdentifierPrefix = "com.victoria.weight"

    // MARK: - Authorization

    /// Request share (write) + read access for body mass.
    ///
    /// Note: HealthKit never reveals read-authorization status for privacy
    /// reasons, so we can't reliably "check" read access — we just request and
    /// let individual operations succeed or come back empty.
    func requestAuthorization() async throws {
        // UI smoke flows: no system permission sheet over the screen under test.
        guard !UITestHooks.isActive else { return }
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard let bodyMassType else { throw HealthKitError.bodyMassTypeUnavailable }

        // `toShare` expects Set<HKSampleType>; `read` expects Set<HKObjectType>.
        // Swift Set is invariant, so build the two sets with their exact element
        // types rather than reusing one (which would fail to type-check).
        let shareTypes: Set<HKSampleType> = [bodyMassType]
        var readSet: Set<HKObjectType> = [bodyMassType]
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            readSet.insert(stepType)
        }
        // Sleep + detected workouts + recovery vitals — how a Fitbit/tracker (bridged
        // into Apple Health) reaches the coach. Read-only; see HealthKitSleepWorkouts.swift.
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            readSet.insert(sleepType)
        }
        readSet.insert(.workoutType())
        for id in [HKQuantityTypeIdentifier.restingHeartRate, .heartRateVariabilitySDNN] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { readSet.insert(t) }
        }
        let readTypes: Set<HKObjectType> = readSet
        // requestAuthorization(toShare:read:) is async-throwing on iOS 15+.
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Saving

    /// Save a weigh-in (in pounds) to Apple Health for the given date.
    ///
    /// Uses `HKMetadataKeySyncIdentifier` + `HKMetadataKeySyncVersion` so that
    /// writing the same logical sample twice updates rather than duplicates.
    func saveWeight(lbs: Double, date: Date) async throws {
        guard Self.isAvailable else { throw HealthKitError.unavailable }
        guard let bodyMassType else { throw HealthKitError.bodyMassTypeUnavailable }

        let quantity = HKQuantity(unit: .pound(), doubleValue: lbs)

        // A stable identifier derived from the timestamp so repeated saves of
        // the same weigh-in collapse to one HealthKit sample.
        let syncID = "\(Self.syncIdentifierPrefix).\(Int(date.timeIntervalSince1970))"
        let metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: syncID,
            HKMetadataKeySyncVersion: 1
        ]

        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )

        try await store.save(sample)
    }

    // MARK: - Importing

    /// A plain, thread-safe snapshot of a HealthKit weight sample, decoupled
    /// from `HKQuantitySample` so it can cross actor boundaries safely.
    private struct ImportableWeight: Sendable {
        let weightLbs: Double
        let healthKitUUID: String
        let date: Date
    }

    /// Import recent body-mass samples (roughly the last 365 days) that were
    /// authored by *other* apps/sources and aren't already tracked locally.
    ///
    /// SwiftData's `ModelContext` is not thread-safe / not `Sendable`, so this
    /// method is pinned to `@MainActor` (matching where the view's environment
    /// context lives). The HealthKit query itself runs on its own queue; we only
    /// read the (thread-safe) `HKQuantitySample` values inside the callback and
    /// return plain value types. The `context.insert(...)` work then happens
    /// back on the main actor, so the context never crosses an actor boundary.
    ///
    /// - Parameters:
    ///   - context: SwiftData context to insert new `WeightEntry` rows into.
    ///   - existingHealthKitUUIDs: HealthKit sample UUID strings already imported.
    /// - Returns: the number of new entries inserted (0 if unavailable/unauthorized).
    @MainActor
    @discardableResult
    func importRecent(
        into context: ModelContext,
        existingHealthKitUUIDs: Set<String>
    ) async throws -> Int {
        // No-op gracefully when Health isn't usable.
        guard Self.isAvailable, let bodyMassType else { return 0 }

        let now = Date()
        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(
            withStart: oneYearAgo,
            end: now,
            options: [.strictStartDate]
        )
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let appSource = HKSource.default() // represents *this* app as a source

        // Capture the (Sendable) store locally so the @Sendable continuation
        // body doesn't capture `self` (HealthKitService is not Sendable).
        let store = self.store

        // Bridge the callback-based HKSampleQuery to async/await. We do all the
        // HealthKit reads here (off the main actor) and return only plain value
        // types, filtered down to the new, third-party samples we want.
        let importables: [ImportableWeight] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortByDate]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantitySamples = (results as? [HKQuantitySample]) ?? []
                let mapped: [ImportableWeight] = quantitySamples.compactMap { sample in
                    // Skip samples this app wrote — we already track those locally.
                    if sample.sourceRevision.source == appSource { return nil }
                    let uuidString = sample.uuid.uuidString
                    if existingHealthKitUUIDs.contains(uuidString) { return nil }
                    return ImportableWeight(
                        weightLbs: sample.quantity.doubleValue(for: .pound()),
                        healthKitUUID: uuidString,
                        date: sample.startDate
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }

        guard !importables.isEmpty else { return 0 }

        // Back on the main actor (this whole method is @MainActor), so inserting
        // into the view's ModelContext is safe.
        for item in importables {
            let entry = WeightEntry(
                date: item.date,
                weightLbs: item.weightLbs,
                source: "healthkit",
                healthKitUUID: item.healthKitUUID
            )
            context.insert(entry)
        }
        return importables.count
    }
}
