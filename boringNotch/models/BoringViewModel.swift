//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI
import TheBoringWorkerNotifier

class BoringViewModel: NSObject, ObservableObject {

	var coordinator = BoringViewCoordinator.shared
	var detector = FullscreenMediaDetector.shared

	let animationLibrary: BoringAnimations = .init()
	let animation: Animation?

	@Published var contentType: ContentType = .normal
	@Published private(set) var notchState: NotchState = .closed

	@Published var dragDetectorTargeting: Bool = false
	@Published var dropZoneTargeting: Bool = false
	@Published var dropEvent: Bool = false
	@Published var anyDropZoneTargeting: Bool = false
	var cancellables: Set<AnyCancellable> = []

	@Published var hideOnClosed: Bool = true
	@Published var isHoveringCalendar: Bool = false
	@Published var isBatteryPopoverActive: Bool = false

	@Published var screen: String?

	@Published var notchSize: CGSize = getClosedNotchSize()
	@Published var closedNotchSize: CGSize = getClosedNotchSize()

	let webcamManager = WebcamManager.shared
	@Published var isCameraExpanded: Bool = false
	@Published var isRequestingAuthorization: Bool = false

	@Published var keepUpdating: Bool = false
	private var updateCancellable: AnyCancellable?

	func startContinuousUpdate() {
		updateCancellable = Timer.publish(every: 0.01, on: .main, in: .common)
			.autoconnect()
			.sink { [weak self] _ in
				guard let self = self, self.keepUpdating else { return }
					// Place the code to update your variable here, e.g.:
				self.screen = NSScreen.screens.first?.localizedName
			}
	}

	func stopContinuousUpdate() {
		updateCancellable?.cancel()
		updateCancellable = nil
	}

	override init() {
		animation = animationLibrary.animation
		super.init()

		notchSize = getClosedNotchSize(screen: screen)
		closedNotchSize = notchSize

		setupCombine()
		setupDetectorObserver()
	}

	deinit {
		destroy()
	}

	func destroy() {
		cancellables.forEach { $0.cancel() }
		cancellables.removeAll()
	}

	private func setupCombine() {
		Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
			.map { $0 || $1 }
			.assign(to: \.anyDropZoneTargeting, on: self)
			.store(in: &cancellables)
	}

	private func setupDetectorObserver() {
		let enabledPublisher = Defaults
			.publisher(.enableFullscreenMediaDetection)
			.map(\.newValue)
			.removeDuplicates()

		let screenPublisher = $screen
			.compactMap { $0 }
			.removeDuplicates()

		let fullscreenStatusPublisher = detector.$fullscreenStatus
			.removeDuplicates()

		Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
			.map { screenName, fullscreenStatus, enabled in
				let isFullscreen = fullscreenStatus[screenName] ?? false
				return enabled && isFullscreen
			}
			.removeDuplicates()
			.receive(on: RunLoop.main)
			.sink { [weak self] shouldHide in
				withAnimation(.smooth) {
					self?.hideOnClosed = shouldHide
				}
			}
			.store(in: &cancellables)
	}

	var effectiveClosedNotchHeight: CGFloat {
		let currentScreen = NSScreen.screens.first { $0.localizedName == screen }
		let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
		return noNotchAndFullscreen ? 0 : closedNotchSize.height
	}

	func toggleCameraPreview() {
		if isRequestingAuthorization { return }

		switch webcamManager.authorizationStatus {
			case .authorized:
				if webcamManager.isSessionRunning {
					webcamManager.stopSession()
					isCameraExpanded = false
				} else if webcamManager.cameraAvailable {
					webcamManager.startSession()
					isCameraExpanded = true
				}

			case .denied, .restricted:
				DispatchQueue.main.async {
					NSApp.setActivationPolicy(.regular)
					NSApp.activate(ignoringOtherApps: true)

					let alert = NSAlert()
					alert.messageText = "Camera Access Required"
					alert.informativeText = "Please allow camera access in System Settings."
					alert.addButton(withTitle: "Open Settings")
					alert.addButton(withTitle: "Cancel")

					if alert.runModal() == .alertFirstButtonReturn,
					   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
						NSWorkspace.shared.open(url)
					}

					NSApp.setActivationPolicy(.accessory)
					NSApp.deactivate()
				}

			case .notDetermined:
				isRequestingAuthorization = true
				webcamManager.checkAndRequestVideoAuthorization()
				DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
					self.isRequestingAuthorization = false
				}

			default:
				break
		}
	}

	func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
		guard let frame = getScreenFrame(screen) else { return false }

		let baseY = frame.maxY - notchSize.height
		let baseX = frame.midX - notchSize.width / 2

		return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
	}

	func open() {
		withAnimation(.bouncy) {
			self.notchSize = openNotchSize
			self.notchState = .open
		}

		MusicManager.shared.forceUpdate()
	}

	func close() {
		withAnimation(.smooth) {
			self.notchSize = getClosedNotchSize(screen: self.screen)
			self.closedNotchSize = self.notchSize
			self.notchState = .closed
		}

		if !TrayDrop.shared.isEmpty && Defaults[.openShelfByDefault] {
			coordinator.currentView = .shelf
		} else if !coordinator.openLastTabByDefault {
			coordinator.currentView = .home
		}
	}

	func closeHello() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
			guard let self = self else { return }
			self.coordinator.firstLaunch = false
			withAnimation(self.animationLibrary.animation) {
				self.close()
			}
		}
	}
}


