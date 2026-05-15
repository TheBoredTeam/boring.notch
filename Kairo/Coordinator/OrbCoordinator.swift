import AppKit
import SwiftUI
import Combine

@MainActor
final class OrbCoordinator: ObservableObject {
    private let hologram: KairoHologramWindow
    private let orbieWindow: OrbieWindow
    let orbieController: OrbieController

    enum VisibleOrb { case hologram, orbie, none }
    @Published private(set) var visible: VisibleOrb = .hologram

    private var cancellables = Set<AnyCancellable>()

    init(hologram: KairoHologramWindow,
         orbieWindow: OrbieWindow,
         orbieController: OrbieController) {
        self.hologram = hologram
        self.orbieWindow = orbieWindow
        self.orbieController = orbieController

        orbieController.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.handleOrbieMode(mode)
            }
            .store(in: &cancellables)

        showHologram(animated: false)
    }

    // MARK: - Public API

    func showOrb() async {
        await handoffToOrbie()
    }

    func present(_ viewID: OrbieViewID, payload: AnyHashable? = nil) async {
        await handoffToOrbie()
        orbieController.show(viewID, payload: payload)
        orbieWindow.resize(to: orbieController.currentSize)
    }

    func returnToHologram() async {
        await handoffToHologram()
    }

    // MARK: - Mode observation

    private func handleOrbieMode(_ mode: OrbieController.Mode) {
        kairoDebug("handleOrbieMode: \(mode), visible: \(visible)")
        switch mode {
        case .idle:
            if visible == .orbie {
                Task { await handoffToHologram() }
            }
        case .expanded, .listening:
            if visible != .orbie {
                kairoDebug("Triggering handoff to Orbie")
                Task { await handoffToOrbie() }
            }
        }
    }

    // MARK: - Handoff

    private func handoffToOrbie() async {
        guard visible != .orbie else {
            kairoDebug("handoffToOrbie: already orbie, skipping")
            return
        }

        let holoPanel = hologram.panel
        kairoDebug("handoffToOrbie: holoPanel=\(String(describing: holoPanel))")
        let holoCenter = holoPanel.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
            ?? defaultCenter()
        kairoDebug("handoffToOrbie: center=\(holoCenter)")

        let orbDims = OrbieSize.orb.dimensions
        orbieWindow.setFrame(NSRect(
            x: holoCenter.x - orbDims.width / 2,
            y: holoCenter.y - orbDims.height / 2,
            width: orbDims.width,
            height: orbDims.height
        ), display: false)

        KairoOrbAnimator.shared.stop()
        kairoDebug("handoffToOrbie: fading out hologram")
        await fadeOut(holoPanel, duration: 0.25)
        holoPanel?.orderOut(nil)

        orbieWindow.alphaValue = 0
        orbieWindow.orderFrontRegardless()
        kairoDebug("handoffToOrbie: fading in orbie, frame=\(orbieWindow.frame)")
        await fadeIn(orbieWindow, duration: 0.25)

        visible = .orbie
        kairoDebug("handoffToOrbie: complete, visible=orbie")
    }

    private func handoffToHologram() async {
        guard visible != .hologram else { return }

        let orbieCenter = NSPoint(
            x: orbieWindow.frame.midX,
            y: orbieWindow.frame.midY
        )

        let holoPanel = hologram.panel
        let holoSize = holoPanel?.frame.size ?? CGSize(width: 500, height: 500)
        holoPanel?.setFrameOrigin(NSPoint(
            x: orbieCenter.x - holoSize.width / 2,
            y: orbieCenter.y - holoSize.height / 2
        ))

        await fadeOut(orbieWindow, duration: 0.25)
        orbieWindow.orderOut(nil)

        holoPanel?.alphaValue = 0
        holoPanel?.orderFrontRegardless()
        KairoOrbAnimator.shared.start()
        await fadeIn(holoPanel, duration: 0.25)

        visible = .hologram
    }

    private func showHologram(animated: Bool) {
        hologram.show()
        orbieWindow.orderOut(nil)
        visible = .hologram
    }

    // MARK: - Animation helpers

    private func fadeOut(_ window: NSWindow?, duration: TimeInterval) async {
        guard let window else { return }
        await withCheckedContinuation { cont in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }, completionHandler: { cont.resume() })
        }
    }

    private func fadeIn(_ window: NSWindow?, duration: TimeInterval) async {
        guard let window else { return }
        await withCheckedContinuation { cont in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }, completionHandler: { cont.resume() })
        }
    }

    private func defaultCenter() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 500, y: 500) }
        return NSPoint(x: screen.visibleFrame.maxX - 120, y: screen.visibleFrame.maxY - 120)
    }
}
