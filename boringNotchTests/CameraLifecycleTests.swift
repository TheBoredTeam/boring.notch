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
    private(set) var startRequests: [String?] = []
    private(set) var stopCount = 0
    private(set) var shutdownCount = 0

    func refresh() {
        refreshCount += 1
    }

    func requestAccess() {
        accessRequestCount += 1
    }

    func start(cameraID: String?) {
        startRequests.append(cameraID)
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
        CameraDevice(id: "built-in", name: "Built-in Camera", isExternal: false),
        CameraDevice(id: "external", name: "External Camera", isExternal: true)
    ]

    func testCameraRequestsPermissionWhenStartingWithoutAuthorization() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        engine.send(.devices(cameras))

        camera.startSession()

        XCTAssertEqual(camera.state, .requestingPermission)
        XCTAssertEqual(engine.accessRequestCount, 1)
        XCTAssertTrue(engine.startRequests.isEmpty)
    }

    func testGrantedPermissionStartsTheCameraAndPublishesPreview() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        engine.send(.devices(cameras))

        camera.startSession()
        engine.send(.authorization(.authorized))

        XCTAssertEqual(camera.authorizationStatus, .authorized)
        XCTAssertEqual(camera.state, .starting)
        XCTAssertEqual(engine.startRequests, ["built-in"])

        let session = AVCaptureSession()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        engine.send(.started(previewLayer: layer, device: cameras[0]))

        XCTAssertTrue(camera.isSessionRunning)
        XCTAssertTrue(camera.previewLayer === layer)
        XCTAssertEqual(camera.selectedCameraID, "built-in")
    }

    func testDeniedPermissionLeavesCameraUnavailableToTheUser() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)

        camera.startSession()
        engine.send(.authorization(.denied))

        XCTAssertEqual(camera.state, .permissionDenied)
        XCTAssertEqual(camera.authorizationStatus, .denied)
        XCTAssertTrue(engine.startRequests.isEmpty)
    }

    func testStoppingTheSharedCameraRemovesPreviewAndStopsCapture() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        camera.stopSession()
        engine.send(.stopped)

        XCTAssertEqual(camera.state, .stopped)
        XCTAssertNil(camera.previewLayer)
        XCTAssertEqual(engine.stopCount, 1)
    }

    func testSelectingAnotherAvailableCameraRequestsAReplacementWithoutChangingThePublicContract() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        camera.selectCamera("external")

        XCTAssertEqual(camera.selectedCameraID, "external")
        XCTAssertEqual(camera.state, .starting)
        XCTAssertEqual(engine.startRequests, ["external"])
    }

    func testAReplacementFailureDoesNotLeaveAStalePreviewVisible() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        camera.selectCamera("external")
        engine.send(.failed("The camera became unavailable"))

        XCTAssertEqual(camera.state, .failed("The camera became unavailable"))
        XCTAssertNil(camera.previewLayer)
    }

    func testDisconnectMakesTheSharedCameraUnavailableWithoutAWindowOwner() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        engine.send(.devices([]))

        XCTAssertEqual(camera.state, .unavailable)
        XCTAssertFalse(camera.cameraAvailable)
        XCTAssertNil(camera.previewLayer)
    }

    func testRecoveryCanRestartTheSameSharedCameraAfterInterruption() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        engine.send(.devices(cameras))
        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        engine.send(.stopped)
        XCTAssertEqual(camera.state, .stopped)

        engine.send(.started(
            previewLayer: AVCaptureVideoPreviewLayer(session: AVCaptureSession()),
            device: cameras[0]
        ))

        XCTAssertTrue(camera.isSessionRunning)
        XCTAssertEqual(camera.selectedCameraID, "built-in")
    }

    func testRepeatedAuthorizedStatusDoesNotTriggerAnotherRefresh() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .authorized)
        XCTAssertEqual(engine.refreshCount, 1)

        // The real engine republishes the authorization status on every refresh.
        engine.send(.authorization(.authorized))
        engine.send(.authorization(.authorized))

        XCTAssertEqual(camera.authorizationStatus, .authorized)
        XCTAssertEqual(engine.refreshCount, 1)
    }

    func testNewlyGrantedPermissionRefreshesDevicesOnce() {
        let engine = CameraEngineStub()
        let camera = CameraModel(engine: engine, authorizationStatus: .notDetermined)
        XCTAssertEqual(engine.refreshCount, 1)

        engine.send(.authorization(.authorized))
        engine.send(.authorization(.authorized))

        XCTAssertEqual(camera.authorizationStatus, .authorized)
        XCTAssertEqual(engine.refreshCount, 2)
    }
}
