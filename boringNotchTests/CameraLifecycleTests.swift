//
//  CameraLifecycleTests.swift
//  boringNotchTests
//
//  Created by Alexander on 2026-09-16.
//

import AVFoundation
import XCTest

@testable import boringNotch

private final class CameraEngineStub: CameraSessionEngine, @unchecked Sendable {
    var eventHandler: (@MainActor @Sendable (CameraSessionEvent) -> Void)?
    private(set) var refreshCount = 0
    private(set) var accessRequestCount = 0
    private(set) var startSelections: [CameraSelection] = []
    private(set) var stopCount = 0
    private(set) var shutdownCount = 0

    func refresh() {
        refreshCount += 1
    }

    func requestAccess() {
        accessRequestCount += 1
    }

    func start(selection: CameraSelection) {
        startSelections.append(selection)
    }

    func stop() {
        stopCount += 1
    }

    func shutdown() {
        shutdownCount += 1
    }

    @MainActor
    func send(_ event: CameraSessionEvent) {
        eventHandler?(event)
    }
}

@MainActor
final class CameraLifecycleTests: XCTestCase {
    private let cameras = [
        CameraDevice(id: "built-in", name: "Built-in Camera", kind: .builtIn),
        CameraDevice(id: "external", name: "External Camera", kind: .external)
    ]

    private func makeRunningCamera(
        engine: CameraEngineStub,
        device: CameraDevice? = nil
    ) -> CameraModel {
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            session: AVCaptureSession(),
            device: device ?? cameras[0]
        ))
        return camera
    }

    private func liveSession() -> AVCaptureSession {
        AVCaptureSession()
    }

    // MARK: - Automatic selection semantics

    func testAutomaticSelectionStaysAutomatic() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        XCTAssertEqual(camera.selection, .automatic)
        // The engine resolved a concrete device, but the user's intent is untouched.
        XCTAssertEqual(camera.activeCameraID, "built-in")

        // A device discovery event must not rewrite the selection.
        engine.send(.devices(cameras))
        XCTAssertEqual(camera.selection, .automatic)

        // Neither must starting and stopping.
        camera.stopSession()
        camera.startSession()
        XCTAssertEqual(camera.selection, .automatic)
        XCTAssertEqual(engine.startSelections.last, .automatic)
    }

    func testSelectingAutomaticAfterASpecificDeviceRestoresThePreference() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.selectCamera(.device("external"))
        XCTAssertEqual(camera.selection, .device("external"))

        camera.selectCamera(.automatic)
        XCTAssertEqual(camera.selection, .automatic)
        // A live session gets nudged so the engine can resolve automatic.
        XCTAssertEqual(engine.startSelections.last, .automatic)
    }

    // MARK: - Deterministic automatic preference

    func testAutomaticPrefersBuiltInOverExternal() {
        let devices = [
            CameraDevice(id: "usb-1", name: "USB Camera", kind: .external),
            CameraDevice(id: "built-in", name: "Built-in", kind: .builtIn)
        ]
        XCTAssertEqual(preferredCamera(from: devices, selection: .automatic)?.id, "built-in")
    }

    func testAutomaticPrefersBuiltInOverContinuityAndContinuityOverExternal() {
        let devices = [
            CameraDevice(id: "cont", name: "Continuity Camera", kind: .continuity),
            CameraDevice(id: "usb-1", name: "USB Camera", kind: .external)
        ]
        XCTAssertEqual(preferredCamera(from: devices, selection: .automatic)?.id, "cont")
    }

    func testAutomaticUsesStableIDTieBreakWithinTheSameKind() {
        let devices = [
            CameraDevice(id: "b-second", name: "ZZZ Camera", kind: .builtIn),
            CameraDevice(id: "a-first", name: "AAA Camera", kind: .builtIn)
        ]
        XCTAssertEqual(preferredCamera(from: devices, selection: .automatic)?.id, "a-first")
    }

    func testSpecificDeviceSelectionWinsOverTheAutomaticPreference() {
        let devices = [
            CameraDevice(id: "built-in", name: "Built-in", kind: .builtIn),
            CameraDevice(id: "usb-1", name: "USB Camera", kind: .external)
        ]
        XCTAssertEqual(preferredCamera(from: devices, selection: .device("usb-1"))?.id, "usb-1")
    }

    func testMissingDeviceResolvesToNilWithoutFallingBack() {
        let devices = [
            CameraDevice(id: "built-in", name: "Built-in", kind: .builtIn)
        ]
        XCTAssertNil(preferredCamera(from: devices, selection: .device("usb-1")))
        XCTAssertNil(preferredCamera(from: [], selection: .automatic))
    }

    // MARK: - Explicit selection vs device lifecycle

    func testExplicitSelectionSurvivesDisconnectAndReconnect() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine, device: cameras[1])
        camera.selectCamera(.device("external"))

        // The selected camera disappears.
        engine.send(.devices([cameras[0]]))
        XCTAssertEqual(camera.selection, .device("external"))
        // The stale session is dropped from the UI.
        XCTAssertNil(camera.activeSession)

        // The same camera returns.
        engine.send(.devices(cameras))
        engine.send(.started(session: liveSession(), device: cameras[1]))

        XCTAssertEqual(camera.selection, .device("external"))
        XCTAssertEqual(camera.activeCameraID, "external")
        // The engine is only ever asked to open the user's device — never a
        // fallback — so reconnecting that uniqueID restores the selection.
        XCTAssertEqual(engine.startSelections, [.device("external")])
    }

    func testAutomaticFallsBackWhenThePreferredCameraDisappears() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine, device: cameras[0])

        // Built-in disappears; automatic may choose the external camera.
        engine.send(.devices([cameras[1]]))
        engine.send(.started(session: liveSession(), device: cameras[1]))

        XCTAssertEqual(camera.selection, .automatic)
        XCTAssertEqual(camera.activeCameraID, "external")
        XCTAssertTrue(camera.isSessionRunning)

        // Built-in returns; automatic may choose it again.
        engine.send(.devices(cameras))
        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertEqual(camera.activeCameraID, "built-in")
    }

    // MARK: - Interruption vs intentional stop

    func testInterruptionIsNotAnIntentionalStop() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        engine.send(.interrupted)

        XCTAssertEqual(camera.state, .interrupted)
        XCTAssertTrue(camera.isIntendedRunning)
        // The model never tears capture down for a system interruption.
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertNotNil(camera.activeSession)

        // Recovery from the interruption side restores the live state.
        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
    }

    func testIntentionalStopClearsTheRunningIntent() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.stopSession()

        XCTAssertEqual(camera.state, .stopped)
        XCTAssertFalse(camera.isIntendedRunning)
        XCTAssertEqual(engine.stopCount, 1)
    }

    // MARK: - Failure handling and recovery intent

    func testRuntimeErrorAfterIntentionalStopDoesNotRestart() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.stopSession()
        engine.send(.failed("Media services were reset"))

        XCTAssertEqual(camera.state, .stopped)
        XCTAssertFalse(camera.isIntendedRunning)
        // No recovery start was issued after the intentional stop.
        XCTAssertEqual(engine.startSelections, [])
    }

    func testRuntimeErrorWhileIntendedRunningKeepsTheRecoveryIntent() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        engine.send(.failed("The camera was reported with a runtime error"))

        XCTAssertEqual(camera.state, .failed("The camera was reported with a runtime error"))
        XCTAssertTrue(camera.isIntendedRunning)
        XCTAssertNil(camera.activeSession)

        // The engine's recovery reports a fresh session; the model accepts it.
        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
    }

    // MARK: - Sleep / wake

    func testSleepInterruptionDoesNotClearUserIntent() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        // Sleep is published as an interruption; the intent stays set so the
        // wake path can recover.
        engine.send(.interrupted)

        XCTAssertEqual(camera.state, .interrupted)
        XCTAssertTrue(camera.isIntendedRunning)
        XCTAssertEqual(camera.activeCameraID, "built-in")
    }

    func testWakeRecoveryRestoresTheActiveCamera() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        engine.send(.interrupted)
        engine.send(.started(session: liveSession(), device: cameras[0]))

        XCTAssertTrue(camera.isSessionRunning)
        XCTAssertTrue(camera.isIntendedRunning)
        XCTAssertEqual(engine.startSelections, [])
    }

    // MARK: - Command ordering

    func testStopFollowedByStartHasDeterministicOrdering() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.stopSession()
        camera.startSession()

        XCTAssertEqual(camera.state, .starting)
        XCTAssertTrue(camera.isIntendedRunning)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(engine.startSelections, [.automatic])

        // A late stopped event from the stop command must not clobber the
        // newer start intent's state.
        engine.send(.stopped)
        XCTAssertEqual(camera.state, .stopped)
        // But the intent survives; the next engine .started is still accepted.
        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
    }

    func testShutdownPreventsLateCallbacksFromChangingState() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.shutdown()
        XCTAssertEqual(engine.shutdownCount, 1)

        // The handler is detached: late engine events cannot resurrect state.
        engine.send(.started(session: liveSession(), device: cameras[0]))
        engine.send(.devices([]))

        XCTAssertEqual(camera.state, .running)
        XCTAssertNotNil(camera.activeSession)
    }

    // MARK: - Camera switching

    func testSwitchingCamerasReplacesTheInputWithoutStoppingTheEngine() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.selectCamera(.device("external"))

        XCTAssertEqual(camera.selection, .device("external"))
        XCTAssertEqual(camera.state, .starting)
        // A switch is a start with the new selection; no stop in between, so
        // the engine can swap the input on the existing session.
        XCTAssertEqual(engine.startSelections, [.device("external")])
        XCTAssertEqual(engine.stopCount, 0)

        engine.send(.started(session: liveSession(), device: cameras[1]))
        XCTAssertEqual(camera.activeCameraID, "external")
        XCTAssertTrue(camera.isSessionRunning)
    }

    func testSelectingTheSameCameraDoesNotRestartTheSession() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.selectCamera(.device("built-in"))

        XCTAssertEqual(engine.startSelections, [])
        XCTAssertEqual(camera.state, .running)
    }

    // MARK: - On-demand lifecycle

    func testSecondStartAfterIntentionalStopIssuesAFreshStartCommand() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.stopSession()
        engine.send(.stopped)
        XCTAssertEqual(camera.state, .stopped)

        // Reopening the notch: the model must issue a new start command —
        // the engine rebuilds a fresh session rather than reviving the dead
        // one, which is what broke second starts.
        camera.startSession()

        XCTAssertEqual(camera.state, .starting)
        XCTAssertTrue(camera.isIntendedRunning)
        // Exactly one fresh start command for the second run (the camera was
        // made running via a .started event, so this is the only command).
        XCTAssertEqual(engine.startSelections, [.automatic])
        XCTAssertNil(camera.activeSession)

        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
        XCTAssertEqual(camera.activeCameraID, "built-in")
    }

    func testStopLeavesNoLiveSessionBehind() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        camera.stopSession()
        engine.send(.stopped)

        // Battery invariant: an intentional stop must leave the model holding
        // no capture session at all, so nothing can keep the sensor alive.
        XCTAssertNil(camera.activeSession)
        XCTAssertNil(camera.activeCameraID)
        XCTAssertFalse(camera.isIntendedRunning)
    }

    func testRepeatedDevicePublicationsWhileRunningDoNotRestartTheSession() {
        let engine = CameraEngineStub()
        let camera = makeRunningCamera(engine: engine)

        // Identical discovery republishes (plugging in unrelated USB devices
        // triggers these) must not churn the capture session.
        engine.send(.devices(cameras))
        engine.send(.devices(cameras))
        engine.send(.devices(cameras))

        XCTAssertEqual(engine.startSelections, [])
        XCTAssertEqual(camera.state, .running)
    }

    func testStartingWithoutCamerasRecordsIntentForLaterRecovery() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices([]))

        camera.startSession()

        XCTAssertEqual(camera.state, .unavailable)
        XCTAssertTrue(camera.isIntendedRunning)
        // The engine is told to run; when a camera appears it recovers.
        XCTAssertEqual(engine.startSelections, [.automatic])

        engine.send(.devices(cameras))
        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
    }

    func testPermissionRequestFlowStillDefersStartUntilAuthorized() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        engine.send(.devices(cameras))

        camera.startSession()

        XCTAssertEqual(camera.state, .requestingPermission)
        XCTAssertEqual(engine.accessRequestCount, 1)
        XCTAssertTrue(engine.startSelections.isEmpty)

        engine.send(.authorization(.authorized))

        XCTAssertEqual(camera.state, .starting)
        XCTAssertEqual(engine.startSelections, [.automatic])

        engine.send(.started(session: liveSession(), device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)
    }

    func testDeniedPermissionClearsTheRunningIntent() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        engine.send(.devices(cameras))

        camera.startSession()
        engine.send(.authorization(.denied))

        XCTAssertEqual(camera.state, .permissionDenied)
        XCTAssertFalse(camera.isIntendedRunning)
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertTrue(engine.startSelections.isEmpty)
    }

    // MARK: - Restored behavioral contract (from the pre-rewrite suite)

    func testStoppingTheSharedCameraRemovesPreviewAndStopsCapture() {
        let engine = CameraEngineStub()
        let session = AVCaptureSession()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(session: session, device: cameras[0]))
        XCTAssertTrue(camera.isSessionRunning)

        camera.stopSession()
        engine.send(.stopped)

        XCTAssertEqual(camera.state, .stopped)
        XCTAssertNil(camera.activeSession)
        XCTAssertFalse(camera.isIntendedRunning)
        XCTAssertEqual(engine.stopCount, 1)
        // The session handed to the preview is distinct from any later one.
        XCTAssertFalse(camera.isSessionRunning)
    }

    func testAReplacementFailureDoesNotLeaveAStalePreviewVisible() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(session: AVCaptureSession(), device: cameras[0]))

        camera.selectCamera(.device("external"))
        engine.send(.failed("The camera became unavailable"))

        XCTAssertEqual(camera.state, .failed("The camera became unavailable"))
        XCTAssertNil(camera.activeSession)
        // The switch intent stays armed so the engine can recover.
        XCTAssertTrue(camera.isIntendedRunning)
    }

    func testDisconnectMakesTheSharedCameraUnavailableWithoutAWindowOwner() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(session: AVCaptureSession(), device: cameras[0]))

        engine.send(.devices([]))

        XCTAssertEqual(camera.state, .unavailable)
        XCTAssertFalse(camera.cameraAvailable)
        XCTAssertNil(camera.activeSession)
        // Intent is preserved so a reconnected camera recovers (review §9).
        XCTAssertTrue(camera.isIntendedRunning)
        // No redundant start was issued for the empty list.
        XCTAssertEqual(engine.startSelections, [])
    }

    func testRepeatedAuthorizedStatusDoesNotTriggerAnotherRefresh() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        let initialRefreshCount = engine.refreshCount

        engine.send(.authorization(.authorized))
        engine.send(.authorization(.authorized))

        XCTAssertEqual(engine.refreshCount, initialRefreshCount)
        XCTAssertTrue(engine.startSelections.isEmpty)
    }

    func testNewlyGrantedPermissionRefreshesDevicesOnce() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        let initialRefreshCount = engine.refreshCount

        camera.startSession()
        engine.send(.authorization(.authorized))

        XCTAssertEqual(engine.refreshCount, initialRefreshCount + 1)
        XCTAssertEqual(engine.startSelections, [.automatic])
    }

    func testGrantedPermissionStartsTheCameraAndPublishesPreview() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        engine.send(.devices(cameras))

        camera.startSession()
        engine.send(.authorization(.authorized))

        XCTAssertEqual(camera.authorizationStatus, .authorized)
        XCTAssertEqual(camera.state, .starting)
        XCTAssertEqual(engine.startSelections, [.automatic])

        let session = AVCaptureSession()
        engine.send(.started(session: session, device: cameras[0]))

        XCTAssertTrue(camera.isSessionRunning)
        XCTAssertTrue(camera.activeSession === session)
        // The engine resolved automatic to the concrete device.
        XCTAssertEqual(camera.activeCameraID, "built-in")
        // The user's selection intent is still automatic.
        XCTAssertEqual(camera.selection, .automatic)
    }
}
