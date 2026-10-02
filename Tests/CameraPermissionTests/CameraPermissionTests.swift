import XCTest
import AVFoundation
@testable import DarkSleep

final class CameraPermissionTests: XCTestCase {
    func testManualTestRequestsPermissionWithoutEnablingMonitoring() {
        var requests = 0
        let model = Model(authorizationStatus: { .notDetermined }, requestAccess: { _ in requests += 1 })
        model.testCamera()
        model.testCamera()
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.promptVisible)
    }

    func testDeniedAndRestrictedDoNotRequestAgainOrEnableMonitoring() {
        for status in [AVAuthorizationStatus.denied, .restricted] {
            let model = Model(authorizationStatus: { status }, requestAccess: { _ in XCTFail("Must not request again") })
            model.testCamera()
            XCTAssertFalse(model.enabled)
            XCTAssertFalse(model.promptVisible)
            XCTAssertEqual(model.status, L("Camera access denied. Allow it in macOS Settings."))
        }
    }

    func testPermissionResponseForMonitoring() {
        for granted in [true, false] {
            var reply: ((Bool) -> Void)?
            let model = Model(authorizationStatus: { .notDetermined }, requestAccess: { reply = $0 })
            model.setEnabled(true)
            reply?(granted)
            let drained = expectation(description: "Permission response")
            DispatchQueue.main.async { drained.fulfill() }
            wait(for: [drained], timeout: 1)
            XCTAssertEqual(model.enabled, granted)
            XCTAssertFalse(model.promptVisible)
            model.setEnabled(false)
        }
    }

    func testCancelledPermissionResultCannotRestartMonitoring() {
        var reply: ((Bool) -> Void)?
        let model = Model(authorizationStatus: { .notDetermined }, requestAccess: { reply = $0 })
        model.setEnabled(true)
        XCTAssertNotNil(reply)
        model.setEnabled(false)
        reply?(true)
        let drained = expectation(description: "Permission callback processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.promptVisible)
        XCTAssertEqual(model.status, L("Off"))
    }
}
