import XCTest
@testable import Sprout

/// Pins the daily recovery signal (Whoop's baseline idea at daily resolution) and the
/// honesty rules around it: no signal without a real personal baseline, `tender` framed
/// by elevated-RHR/suppressed-HRV only, and never from a single metric blip.
final class RecoverySignalTests: XCTestCase {

    // MARK: - Core thresholds

    func testElevatedRHRIsTender() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: 66, baselineRHR: 60,
                                              todayHRV: nil, baselineHRV: nil), .tender)
    }

    func testSuppressedHRVIsTender() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: nil, baselineRHR: nil,
                                              todayHRV: 30, baselineHRV: 45), .tender)
    }

    func testLowRHRIsRested() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: 57, baselineRHR: 60,
                                              todayHRV: nil, baselineHRV: nil), .rested)
    }

    func testHighHRVIsRested() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: nil, baselineRHR: nil,
                                              todayHRV: 55, baselineHRV: 45), .rested)
    }

    func testNormalWiggleIsSteady() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: 61, baselineRHR: 60,
                                              todayHRV: 44, baselineHRV: 45), .steady)
    }

    /// Load evidence outranks rest evidence — an elevated RHR with a good HRV still
    /// reads tender (the body is saying something; don't average it away).
    func testTenderWinsOverRested() {
        XCTAssertEqual(RecoverySignal.compute(todayRHR: 66, baselineRHR: 60,
                                              todayHRV: 55, baselineHRV: 45), .tender)
    }

    func testNoDataMeansNoSignal() {
        XCTAssertNil(RecoverySignal.compute(todayRHR: nil, baselineRHR: nil,
                                            todayHRV: nil, baselineHRV: nil))
        // Today's value without a baseline (or vice versa) is not comparable — stay silent.
        XCTAssertNil(RecoverySignal.compute(todayRHR: 60, baselineRHR: nil,
                                            todayHRV: nil, baselineHRV: nil))
    }

    // MARK: - Daily-rows path (baseline requires ≥5 days)

    func testDailyVitalsNeedsFiveBaselineDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func entry(_ daysAgo: Int, rhr: Double) -> VitalsEntry {
            VitalsEntry(date: cal.date(byAdding: .day, value: -daysAgo, to: today)!,
                        restingHeartRate: rhr)
        }
        // Only 3 baseline days → not enough to claim a baseline → nil.
        let sparse = [entry(0, rhr: 66), entry(1, rhr: 60), entry(2, rhr: 60), entry(3, rhr: 60)]
        XCTAssertNil(RecoverySignal.fromDailyVitals(sparse))

        // 6 baseline days at 60, today at 66 → tender.
        let full = [entry(0, rhr: 66)] + (1...6).map { entry($0, rhr: 60) }
        XCTAssertEqual(RecoverySignal.fromDailyVitals(full), .tender)
    }

    // MARK: - Copy contract: warm, never clinical or alarming

    func testCopyNeverAlarms() {
        for signal in [RecoverySignal.rested, .steady, .tender] {
            let text = (signal.label + " " + signal.sentence + " " + signal.coachLine).lowercased()
            for banned in ["stress score", "danger", "warning", "abnormal", "concerning",
                           "see a doctor", "medical", "alert"] {
                XCTAssertFalse(text.contains(banned), "\(signal) copy contained '\(banned)'")
            }
        }
        // Tender must point toward gentleness, not pushing through.
        XCTAssertTrue(RecoverySignal.tender.sentence.lowercased().contains("gentle"))
    }
}
