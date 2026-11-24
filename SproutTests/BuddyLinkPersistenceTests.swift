import XCTest
@testable import Sprout

/// Regression tests for the bug where pairing was lost every time the app was closed:
/// the linked buddy lived only in memory, so relaunching dropped both users back to the
/// pairing screen even though the CloudKit pairing records still existed.
///
/// The fix persists `buddyUserID` to `UserDefaults` (CloudKit backend) and restores it in
/// `init`, exposed via `linkedBuddyID`, so a FRESH service instance (== an app relaunch)
/// comes back already paired. These tests are network-free: they exercise only the
/// persistence/restore path, not CloudKit itself.
@MainActor
final class BuddyLinkPersistenceTests: XCTestCase {

    /// A saved CloudKit link must be restored by a brand-new service instance.
    func testCloudKitLinkSurvivesNewServiceInstance() {
        let myID = "test-\(UUID().uuidString)"
        let key = "buddy.ck.linkedTo.\(myID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // No link yet → nothing restored.
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(CloudKitSyncService(myUserID: myID).linkedBuddyID,
                     "A fresh install with no saved link should not look paired")

        // Simulate a saved pairing (what `buddyUserID`'s didSet writes on a successful link).
        UserDefaults.standard.set("buddy-XYZ", forKey: key)

        // A brand-new instance (as created on app relaunch) restores the link.
        let restored = CloudKitSyncService(myUserID: myID)
        XCTAssertEqual(restored.linkedBuddyID, "buddy-XYZ",
                       "Relaunch must restore the linked buddy from persistence")
    }

    /// The ViewModel must come up already paired at launch when a link is persisted —
    /// i.e. no flash of the pairing screen, no lost pairing.
    func testViewModelRestoresLinkedStateAtLaunch() {
        let myID = "test-\(UUID().uuidString)"
        let key = "buddy.ck.linkedTo.\(myID)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("buddy-XYZ", forKey: key)
        let vm = BuddyViewModel(service: CloudKitSyncService(myUserID: myID), myUserID: myID)
        XCTAssertTrue(vm.isLinked, "Restored link should mark the VM as linked at launch")
    }

    /// Without a saved link, the ViewModel comes up unpaired (shows the pairing screen).
    func testViewModelUnlinkedWhenNoSavedLink() {
        let myID = "test-\(UUID().uuidString)"
        let key = "buddy.ck.linkedTo.\(myID)"
        UserDefaults.standard.removeObject(forKey: key)
        let vm = BuddyViewModel(service: CloudKitSyncService(myUserID: myID), myUserID: myID)
        XCTAssertFalse(vm.isLinked)
    }
}
