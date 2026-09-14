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
    private let configurationStarted: DispatchSemaphore?
    private let configurationGate: DispatchSemaphore?
    private let failFirstConfiguration: Bool
    private var storedDiscoveryCount = 0
    private var storedSessions: [FakeCaptureSession] = []
    private var storedPreferredIDs: [String?] = []

    init(
        configurationStarted: DispatchSemaphore? = nil,
        configurationGate: DispatchSemaphore? = nil,
        failFirstConfiguration: Bool = false
    ) {
        self.failFirstConfiguration = failFirstConfiguration
        self.configurationStarted = configurationStarted
        self.configurationGate = configurationGate
    }

    var sessions: [FakeCaptureSession] {
        lock.withTestLock { storedSessions }
    }

    var preferredIDs: [String?] {
        lock.withTestLock { storedPreferredIDs }
    }

    var discoveryCount: Int {
        lock.withTestLock { storedDiscoveryCount }
    }

    func discoverDevices() -> [AVCaptureDevice] {
        lock.withTestLock { storedDiscoveryCount += 1 }
        return []
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
    ) throws -> String? {
        let attempt = lock.withTestLock {
            storedPreferredIDs.append(preferredID)
            return storedPreferredIDs.count
        }
        if attempt == 1 {
            configurationStarted?.signal()
            configurationGate?.wait()
            if failFirstConfiguration { throw WebcamManager.WebcamError.deviceUnavailable }
        }
        return preferredID ?? "automatic-camera"
    }
}

@MainActor
final class CameraLifecycleTests: XCTestCase {
    private let notificationCenter = NotificationCenter()
    private let workspaceNotificationCenter = NotificationCenter()
    private let sessionQueue = DispatchQueue(label: "CameraLifecycleTests.session")

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

    func testRecoveryAndSelectionWaitForPendingAuthorization() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        var result: WebcamManager.SessionStartResult?
        manager.startSession { result = $0 }

        workspaceNotificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        notificationCenter.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        manager.setSelectedCamera(id: "new-selection")
        sessionQueue.sync {}

        XCTAssertTrue(factory.sessions.isEmpty)
        XCTAssertNil(result)
        XCTAssertTrue(manager.isRequestingAuthorization)
        XCTAssertTrue(manager.isSessionDesired)
        permission.resolve(granted: true)
        waitUntil { result == .started }
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertEqual(factory.preferredIDs, ["new-selection"])
    }

    func testUnrelatedOwnerCannotCancelPendingOrRunningCamera() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        let firstOwner = UUID()
        let otherOwner = UUID()
        var result: WebcamManager.SessionStartResult?
        manager.startSession(owner: firstOwner) { result = $0 }
        manager.stopSession(owner: otherOwner)
        XCTAssertTrue(manager.ownsSession(firstOwner))
        XCTAssertNil(result)

        permission.resolve(granted: true)
        waitUntil { result == .started }
        manager.stopSession(owner: otherOwner)
        XCTAssertTrue(manager.isSessionRunning)
        manager.stopSession(owner: firstOwner)
        sessionQueue.sync {}
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertFalse(factory.sessions[0].isRunning)
    }

    func testOwnerCanCancelPendingPermissionAndTransferCannotBeStoppedByOldOwner() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        let firstOwner = UUID()
        let secondOwner = UUID()
        var result: WebcamManager.SessionStartResult?
        manager.startSession(owner: firstOwner) { result = $0 }
        manager.stopSession(owner: firstOwner)
        XCTAssertEqual(result, .cancelled)
        manager.startSession(owner: secondOwner)
        manager.stopSession(owner: firstOwner)
        permission.resolve(granted: true)
        waitUntil { manager.isSessionRunning }
        XCTAssertTrue(manager.ownsSession(secondOwner))
        XCTAssertEqual(factory.sessions.count, 1)

        manager.startSession(owner: firstOwner)
        manager.stopSession(owner: secondOwner)
        waitUntil { manager.isSessionRunning && factory.sessions.count == 2 }
        XCTAssertTrue(manager.ownsSession(firstOwner))
        XCTAssertFalse(factory.sessions[0].isRunning)
    }

    func testOwnerTeardownFromBackgroundCancelsPendingStart() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        let owner = UUID()
        var result: WebcamManager.SessionStartResult?

        manager.startSession(owner: owner) { result = $0 }
        DispatchQueue.global().async {
            manager.releaseSession(owner: owner)
        }

        waitUntil { result == .cancelled }
        permission.resolve(granted: true)
        sessionQueue.sync {}

        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertTrue(factory.sessions.isEmpty)
    }

    func testOwnerTeardownStopsOnlyItsActiveSession() {
        let permission = PermissionStub(status: .authorized)
        let factory = SessionFactory()
        let manager = makeManager(permission: permission, factory: factory)
        let owner = UUID()
        let unrelatedOwner = UUID()

        manager.startSession(owner: owner)
        waitUntil { manager.isSessionRunning && factory.sessions.count == 1 }

        manager.releaseSession(owner: unrelatedOwner)
        XCTAssertTrue(manager.ownsSession(owner))
        XCTAssertTrue(manager.isSessionRunning)

        manager.releaseSession(owner: owner)
        sessionQueue.sync {}
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertFalse(factory.sessions[0].isRunning)
    }

    func testOwnerTeardownDuringSetupPreventsLateStart() {
        let permission = PermissionStub(status: .authorized)
        let configurationStarted = DispatchSemaphore(value: 0)
        let configurationGate = DispatchSemaphore(value: 0)
        let factory = SessionFactory(
            configurationStarted: configurationStarted,
            configurationGate: configurationGate
        )
        let manager = makeManager(permission: permission, factory: factory)
        let owner = UUID()
        var result: WebcamManager.SessionStartResult?

        manager.startSession(owner: owner) { result = $0 }
        XCTAssertEqual(configurationStarted.wait(timeout: .now() + 1), .success)

        manager.releaseSession(owner: owner)
        configurationGate.signal()
        sessionQueue.sync {}

        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertFalse(factory.sessions[0].isRunning)
    }

    func testPermissionPublicationStartsANewAttemptAfterSelectionFailure() {
        let permission = PermissionStub(status: .notDetermined)
        let factory = SessionFactory(failFirstConfiguration: true)
        let manager = makeManager(permission: permission, factory: factory)
        let owner = UUID()
        var results: [WebcamManager.SessionStartResult] = []
        manager.startSession(owner: owner) { results.append($0) }

        // Authorization is granted on the system callback queue, but its main
        // continuation is delayed while the settings picker starts a failed setup.
        let permissionResolved = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            permission.resolve(granted: true)
            permissionResolved.signal()
        }
        XCTAssertEqual(permissionResolved.wait(timeout: .now() + 1), .success)
        manager.setSelectedCamera(id: "selected-after-grant")
        sessionQueue.sync {}
        XCTAssertEqual(factory.sessions.count, 1)
        XCTAssertTrue(results.isEmpty)

        waitUntil { !results.isEmpty }
        XCTAssertEqual(results, [.started])
        XCTAssertTrue(manager.ownsSession(owner))
        XCTAssertTrue(manager.isSessionRunning)
        XCTAssertEqual(factory.sessions.count, 2)
        XCTAssertTrue(manager.previewLayer?.session === factory.sessions.last)
        manager.stopSession(owner: owner)
        sessionQueue.sync {}
        XCTAssertTrue(factory.sessions.allSatisfy { !$0.isRunning })
    }

    func testCurrentConfigurationFailureReleasesOwnerAndAllowsRetry() {
        let factory = SessionFactory(failFirstConfiguration: true)
        let manager = makeManager(permission: PermissionStub(status: .authorized), factory: factory)
        let owner = UUID()
        var result: WebcamManager.SessionStartResult?
        manager.startSession(owner: owner) { result = $0 }
        waitUntil { result != nil }
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(manager.ownsSession(owner))
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertFalse(manager.isSessionRunning)
        XCTAssertNil(manager.previewLayer)
        XCTAssertFalse(factory.sessions[0].isRunning)

        manager.startSession(owner: owner)
        waitUntil { manager.isSessionRunning }
        XCTAssertTrue(manager.ownsSession(owner))
        XCTAssertEqual(factory.sessions.count, 2)
        manager.stopSession(owner: owner)
        sessionQueue.sync {}
        XCTAssertTrue(factory.sessions.allSatisfy { !$0.isRunning })
    }

    func testStaleConfigurationFailureCannotCancelSuccessfulReplacement() {
        assertReplacementSurvivesDelayedPublication(failFirstConfiguration: true)
    }

    func testStaleConfigurationSuccessCannotReplaceNewPreview() {
        assertReplacementSurvivesDelayedPublication(failFirstConfiguration: false)
    }

    private func assertReplacementSurvivesDelayedPublication(failFirstConfiguration: Bool) {
        let configurationStarted = DispatchSemaphore(value: 0)
        let configurationGate = DispatchSemaphore(value: 0)
        let factory = SessionFactory(
            configurationStarted: configurationStarted,
            configurationGate: configurationGate,
            failFirstConfiguration: failFirstConfiguration
        )
        let manager = makeManager(permission: PermissionStub(status: .authorized), factory: factory)
        let owner = UUID()
        var results: [WebcamManager.SessionStartResult] = []
        manager.startSession(owner: owner) { results.append($0) }
        XCTAssertEqual(configurationStarted.wait(timeout: .now() + 1), .success)

        // A is already inside configuration. Keep main occupied until both A and B
        // have finished, so A's publication cannot run before B starts capturing.
        manager.setSelectedCamera(id: "replacement-camera")
        configurationGate.signal()
        sessionQueue.sync {}
        XCTAssertEqual(factory.sessions.count, 2)
        guard factory.sessions.count == 2 else { return }
        let replacement = factory.sessions[1]
        XCTAssertTrue(replacement.isRunning)
        XCTAssertTrue(results.isEmpty)

        waitUntil { !results.isEmpty }
        XCTAssertEqual(results, [.started])
        XCTAssertTrue(manager.ownsSession(owner))
        XCTAssertTrue(manager.isSessionRunning)
        XCTAssertTrue(manager.previewLayer?.session === replacement)
        XCTAssertFalse(factory.sessions[0].isRunning)
        XCTAssertTrue(replacement.isRunning)
        XCTAssertEqual(replacement.stopCount, 0)

        manager.stopSession(owner: owner)
        sessionQueue.sync {}
        XCTAssertFalse(replacement.isRunning)
        XCTAssertEqual(replacement.stopCount, 1)
    }

    func testIdleDisconnectRefreshesDiscovery() {
        let factory = SessionFactory()
        let manager = makeManager(permission: PermissionStub(status: .authorized), factory: factory)
        sessionQueue.sync {}
        let initialDiscoveryCount = factory.discoveryCount

        notificationCenter.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        sessionQueue.sync {}

        XCTAssertEqual(factory.discoveryCount, initialDiscoveryCount + 1)
        XCTAssertFalse(manager.isSessionDesired)
        XCTAssertTrue(factory.sessions.isEmpty)
    }

    func testUnownedDisconnectRefreshesDiscoveryWithoutStoppingCapture() {
        let factory = SessionFactory()
        let manager = makeManager(permission: PermissionStub(status: .authorized), factory: factory)
        let owner = UUID()
        manager.startSession(owner: owner)
        waitUntil { manager.isSessionRunning }
        let initialDiscoveryCount = factory.discoveryCount
        XCTAssertTrue(manager.cameraAvailable)

        notificationCenter.post(name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        sessionQueue.sync {}
        waitUntil { !manager.cameraAvailable }

        XCTAssertEqual(factory.discoveryCount, initialDiscoveryCount + 1)
        XCTAssertTrue(manager.availableCameras.isEmpty)
        XCTAssertTrue(manager.ownsSession(owner))
        XCTAssertTrue(factory.sessions[0].isRunning)
        manager.stopSession(owner: owner)
        sessionQueue.sync {}
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
                discoverDevices: factory.discoverDevices,
                configureSession: factory.configure,
                makeSession: factory.makeSession,
                makePreviewLayer: { AVCaptureVideoPreviewLayer(session: $0) },
                notificationCenter: notificationCenter,
                workspaceNotificationCenter: workspaceNotificationCenter,
                persistSelectedCamera: { _ in }
            ),
            selectedCameraID: selectedCameraID,
            sessionQueue: sessionQueue
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
