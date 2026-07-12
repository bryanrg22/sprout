import XCTest
@testable import Victoria

/// Pins the plan-research response cache: goal-band keying (close goals share an
/// evidence base; direction flips miss), the 30-day TTL, and expiry cleanup.
final class ResearchCacheTests: XCTestCase {

    func testKeyBucketsGoalsAndSplitsDirections() {
        // 142 lb and 148 lb share a band → cache hit across small goal tweaks.
        XCTAssertEqual(ResearchCache.key(direction: .lose, goalWeightLbs: 142),
                       ResearchCache.key(direction: .lose, goalWeightLbs: 148))
        // A different band or a direction flip must MISS (new premises → real research).
        XCTAssertNotEqual(ResearchCache.key(direction: .lose, goalWeightLbs: 142),
                          ResearchCache.key(direction: .lose, goalWeightLbs: 155))
        XCTAssertNotEqual(ResearchCache.key(direction: .lose, goalWeightLbs: 142),
                          ResearchCache.key(direction: .gain, goalWeightLbs: 142))
    }

    func testRoundTripAndTTLExpiry() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "research-cache-tests"))
        d.removePersistentDomain(forName: "research-cache-tests")
        let key = ResearchCache.key(direction: .lose, goalWeightLbs: 140)
        let now = Date()

        XCTAssertNil(ResearchCache.lookup(key: key, now: now, defaults: d))
        ResearchCache.store("Protein 1.6 g/kg (examine.com)…", key: key, now: now, defaults: d)
        XCTAssertEqual(ResearchCache.lookup(key: key, now: now, defaults: d),
                       "Protein 1.6 g/kg (examine.com)…")

        // Day 29: still fresh. Day 31: expired AND evicted.
        let day29 = now.addingTimeInterval(29 * 86_400)
        XCTAssertNotNil(ResearchCache.lookup(key: key, now: day29, defaults: d))
        let day31 = now.addingTimeInterval(31 * 86_400)
        XCTAssertNil(ResearchCache.lookup(key: key, now: day31, defaults: d))
        XCTAssertNil(d.data(forKey: key), "expired entries are cleaned up, not hoarded")
    }

    func testEmptyBriefsAreNeverStored() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "research-cache-tests-2"))
        d.removePersistentDomain(forName: "research-cache-tests-2")
        ResearchCache.store("", key: "researchCache.test", defaults: d)
        XCTAssertNil(ResearchCache.lookup(key: "researchCache.test", defaults: d))
    }
}
