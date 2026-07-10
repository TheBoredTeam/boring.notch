//
//  LottieView.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-14.
//

import SwiftUI
import Lottie

private final class LottieHostView: NSView {
    let animationView = LottieAnimationView()
    private(set) var currentURL: URL?
    private var shouldLoop = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPlayback),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPlayback),
            name: NSApplication.didChangeOcclusionStateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPlayback),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshPlayback()
    }

    func configure(url: URL, speed: Double, loopMode: LottieLoopMode) {
        animationView.loopMode = loopMode
        animationView.animationSpeed = CGFloat(speed)
        shouldLoop = true

        guard currentURL != url else {
            refreshPlayback()
            return
        }

        currentURL = url
        animationView.pause()
        LottieAnimation.loadedFrom(url: url) { [weak self] animation in
            guard let self, self.currentURL == url else { return }
            self.animationView.animation = animation
            self.refreshPlayback()
        }
    }

    @objc private func refreshPlayback() {
        let isVisible = window?.occlusionState.contains(.visible) == true && !NSApp.isHidden
        if shouldLoop && isVisible && !ProcessInfo.processInfo.isLowPowerModeEnabled {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        } else {
            animationView.pause()
        }
    }
}

struct LottieView: NSViewRepresentable {
    let url: URL
    let speed: Double
    let loopMode: LottieLoopMode

    func makeNSView(context: Context) -> NSView {
        LottieHostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostView = nsView as? LottieHostView else { return }
        hostView.configure(url: url, speed: speed, loopMode: loopMode)
    }
}
