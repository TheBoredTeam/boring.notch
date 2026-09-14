//
//  CameraLifecycleTests.swift
//  boringNotchTests
//

import AVFoundation
import XCTest

@testable import boringNotch

private final class FakeCaptureSession: AVCaptureSession, @unchecked Sendable {
    private let stateLock = NSLock()
    private var fakeRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    override var isRunning: Bool {
        stateLock.withTestLock { fakeRunning }
    }

    override func startRunning() {
        stateLock.withTestLock {
            startCount += 1
            fakeRunning = true
        }
    }

    override func stopRunning() {
        stateLock.withTestLock {
            stopCount += 1
            fakeRunning = false
        }
    }

    func simulateInterruption() {
        stateLock.withTestLock {
            fakeRunning = false
        }
    }
}

private final class PermissionStub: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: AVAuthorizationStatus
    private var requestCompletion: (@Sendable (Bool) -> Void)?
    private var storedRequestCount = 0

    init(status: AVAuthorizationStatus) {
        storedStatus = status
    }

    var status: AVAuthorizationStatus {
        lock.withTestLock { storedStatus }
    }

    var requestCount: Int {
        lock.withTestLock { storedRequestCount }
    }

    func requestAccess(completion: @escaping @Sendable (Bool) -> Void) {
        lock.withTestLock {
            storedRequestCount += 1
            requestCompletion = completion
        }
    }

    func resolve(granted: Bool) {
        let completion = lock.withTestLock { () -> (@Sendable (Bool) -> Void)? in
            storedStatus = granted ? .authorized : .denied
            defer { requestCompletion = nil }
            return requestCompletion
        }
        completion?(granted)
    }
}

private final class SessionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSessions: [FakeCaptureSession] = []
    private var storedPreferredIDs: [String?] = []

    var sessions: [FakeCaptureSession] {
        lock.withTestLock { storedSessions }
    }

    var preferredIDs: [String?] {
        lock.withTestLock { storedPreferredIDs }
    }

    func makeSession() -> AVCaptureSession {
        let session = FakeCaptureSession()
        lock.withTestLock {
            storedSessions.append(session)
        }
        return session
    }

    func configure(
        session: AVCaptureSession,
        devices: [AVCaptureDevice],
        preferredID: String?
    ) -> String? {
        lock.withTestLock {
            storedPreferredIDs.append(preferredID)
        }
        return preferredID ?? "automatic-camera"
    }
}

@MainActor
final class CameraLifecycleTests: XCTestCase {
    private let notificationCenter = NotificationCenter()
    private let workspaceNotificationCenter = NotificationCenter()

    func testFirstAuthorizationGrantFinishesOriginalStartRequest() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        var result: WebcamManager.SessionStartResult?

        manager.startSession { result = $0 }

        XCTAssertTrue(manager.isSessionDesired)
        XCTAssertTrue(manager.isRequestingAuthorization)
        XCTAssertNil(result)

        permission.resolve(granted: true)

        waitUntil { result == .started }
        XCTAssertTrue(manager.isSessionRunning)
        XCTAssertFalse(manager.isRequestingAuthorization)
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertTrue(factory.sessions[0].isRunning)
    }

    func testPermissionCompletionAfterStopDoesNotCreateSession() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        var result: WebcamManager.SessionStartResult?

        manager.startSession { result = $0 }
        manager.stopSession()
        permission.resolve(granted: true)

        waitUntil { result == .cancelled }
        waitUntil { !manager.isRequestingAuthorization }
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertNil(manager.previewLayer)
        XCTAssertTrue(factory.sessions.isEmpty)
    }

    func testCloseAndReopenDuringPermissionUsesThePendingSystemRequest() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        var firstResult: WebcamManager.SessionStartResult?
        var secondResult: WebcamManager.SessionStartResult?

        manager.startSession { firstResult = $0 }
        manager.stopSession()
        manager.startSession { secondResult = $0 }

        XCTAssertEqual(firstResult, .cancelled)
        XCTAssertNil(secondResult)
        XCTAssertEqual(permission.requestCount, 1)

        permission.resolve(granted: true)

        waitUntil { secondResult == .started }
        XCTAssertTrue(manager.isSessionDesired)
        XCTAssertTrue(manager.isSessionRunning)
        XCTAssertEqual(factory.sessions.count, 1)
    }

    func testRapidStartStopConvergesToStoppedWithoutPublishedLayer() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        var result: WebcamManager.SessionStartResult?

        manager.startSession { result = $0 }
        manager.stopSession()

        waitUntil { result == .cancelled }
        waitUntil { factory.sessions.allSatisfy { !$0.isRunning } }
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertNil(manager.previewLayer)
    }

    func testStopThenRestartUsesANewCurrentSession() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)

        manager.startSession()
        waitUntil { manager.isSessionRunning && factory.sessions.count == 1 }
        let firstSession = factory.sessions[0]

        manager.stopSession()
        waitUntil { !firstSession.isRunning && !manager.isSessionRunning }

        manager.startSession()
        waitUntil { manager.isSessionRunning && factory.sessions.count == 2 }
        let secondSession = factory.sessions[1]

        XCTAssertFalse(firstSession.isRunning)
        XCTAssertEqual(firstSession.stopCount, 1)
        XCTAssertTrue(secondSession.isRunning)
        XCTAssertTrue(manager.previewLayer?.session === secondSession)
    }

    func testRuntimeErrorRecreatesOnlyTheDesiredSession() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)

        manager.startSession()
        waitUntil { manager.isSessionRunning && factory.sessions.count == 1 }
        let failedSession = factory.sessions[0]

        notificationCenter.post(name: AVCaptureSession.runtimeErrorNotification, object: failedSession)

        waitUntil { manager.isSessionRunning && factory.sessions.count == 2 }
        XCTAssertFalse(failedSession.isRunning)
        XCTAssertTrue(factory.sessions[1].isRunning)
        XCTAssertTrue(manager.isSessionDesired)

        manager.stopSession()
        waitUntil { !manager.isSessionRunning }
        notificationCenter.post(name: AVCaptureSession.runtimeErrorNotification, object: factory.sessions[1])
        waitUntil { factory.sessions.allSatisfy { !$0.isRunning } }
        XCTAssertEqual(factory.sessions.count, 2)
    }

    func testInterruptionEndRestartsExistingSession() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)

        manager.startSession()
        waitUntil { manager.isSessionRunning && factory.sessions.count == 1 }
        let session = factory.sessions[0]
        session.simulateInterruption()

        notificationCenter.post(name: AVCaptureSession.wasInterruptedNotification, object: session)
        waitUntil { !manager.isSessionRunning }
        notificationCenter.post(name: AVCaptureSession.interruptionEndedNotification, object: session)

        waitUntil { manager.isSessionRunning }
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertEqual(session.startCount, 2)
    }

    func testWakeRestartsExistingStoppedSession() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)

        manager.startSession()
        waitUntil { manager.isSessionRunning && factory.sessions.count == 1 }
        let session = factory.sessions[0]
        workspaceNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        waitUntil { !manager.isSessionRunning && !session.isRunning }

        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        waitUntil { manager.isSessionRunning }
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertEqual(session.startCount, 2)
    }

    func testExplicitSelectedDeviceIsPassedToConfiguration() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(
            permission: permission,
            factory: factory,
            selectedCameraID: "selected-device"
        )

        manager.startSession()

        waitUntil { manager.isSessionRunning }
        XCTAssertEqual(factory.preferredIDs.count, 1)
        XCTAssertEqual(factory.preferredIDs[0], "selected-device")
    }

    func testPreviewRepresentableReplacesAndDetachesLayers() {
        let firstLayer = AVCaptureVideoPreviewLayer(session: FakeCaptureSession())
        let secondLayer = AVCaptureVideoPreviewLayer(session: FakeCaptureSession())
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        view.wantsLayer = true

        WebcamPreviewLayer.attach(firstLayer, to: view)
        XCTAssertTrue(view.layer === firstLayer)
        XCTAssertEqual(firstLayer.frame, view.bounds)
        XCTAssertEqual(firstLayer.videoGravity, .resizeAspectFill)

        WebcamPreviewLayer.attach(secondLayer, to: view)
        XCTAssertTrue(view.layer === secondLayer)
        XCTAssertEqual(secondLayer.frame, view.bounds)

        WebcamPreviewLayer.dismantleNSView(view, coordinator: ())
        XCTAssertNil(view.layer)
    }

    private func makeManager(
        permission: PermissionStub,
        factory: SessionFactory,
        selectedCameraID: String? = nil
    ) -> WebcamManager {
        WebcamManager(
            dependencies: WebcamManager.Dependencies(
                authorizationStatus: { permission.status },
                requestAccess: permission.requestAccess,
                discoverDevices: { [] },
                configureSession: factory.configure,
                makeSession: factory.makeSession,
                makePreviewLayer: { AVCaptureVideoPreviewLayer(session: $0) },
                notificationCenter: notificationCenter,
                workspaceNotificationCenter: workspaceNotificationCenter
            ),
            selectedCameraID: selectedCameraID,
            sessionQueue: DispatchQueue(label: "CameraLifecycleTests.session")
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "condition did not become true", file: file, line: line)
    }
}

private extension NSLock {
    func withTestLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
