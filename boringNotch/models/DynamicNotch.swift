//
//  DynamicNotch.swift
//  boringNotch
//
//  Created by Richard Kunkli on 12/08/2024.
//

import SwiftUI

public class DynamicNotch: ObservableObject {
    public var content: AnyView
    public var windowController: NSWindowController? // In case user wants to modify the NSPanel
    
    @Published public var isVisible: Bool = false
    @Published var isMouseInside: Bool = false
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 0
    @Published var notchStyle: Style = .notch
    
    private var timer: Timer?
    private let animationDuration: Double = 0.4
    
    private var animation: Animation {
        if #available(macOS 14.0, *), notchStyle == .notch {
            Animation.spring(.bouncy(duration: 0.4))
        } else {
            Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
        }
    }
    
    /// Makes a new DynamicNotch with custom content and style.
    /// - Parameters:
    ///   - content: A SwiftUI View
    ///   - style: The popover's style. If unspecified, the style will be automatically set according to the screen.
    public init(content: some View) {
        self.content = AnyView(content)
    }
    
    // MARK: Public methods
    
    /// Set this DynamicNotch's content.
    /// - Parameter content: A SwiftUI View
    public func setContent(content: some View) {
        self.content = AnyView(content)
        if let windowController {
            windowController.window?.contentView = NSHostingView(rootView: EditPanelView())
        }
    }
    
    /// Show the DynamicNotch.
    /// - Parameters:
    ///   - screen: Screen to show on. Default is the primary screen.
    ///   - time: Time to show in seconds. If 0, the DynamicNotch will stay visible until `hide()` is called.
    public func show(on screen: NSScreen = NSScreen.screens[0], for time: Double = 0) {
        if isVisible { return }
        timer?.invalidate()
        
        initializeWindow(screen: screen)
        
        DispatchQueue.main.async {
            withAnimation(self.animation) {
                self.isVisible = true
            }
        }
        
        if time != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                self.hide()
            }
        }
    }
    
    /// Hide the DynamicNotch.
    public func hide() {
        guard isVisible else { return }
        
        guard !isMouseInside else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.hide()
            }
            return
        }
        
        withAnimation(animation) {
            self.isVisible = false
        }
        
        timer = Timer.scheduledTimer(
            withTimeInterval: animationDuration * 2,
            repeats: false
        ) { _ in
            self.deinitializeWindow()
        }
    }
    
    /// Toggle the DynamicNotch's visibility.
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    private func initializeWindow(screen: NSScreen) {
        // so that we don't have a duplicate window
        deinitializeWindow()
        
        let view: NSView = NSHostingView(rootView: EditPanelView())
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.hasShadow = false
        panel.level = .mainMenu + 1
        panel.collectionBehavior = .canJoinAllSpaces
        panel.contentView = view
        panel.animationBehavior = .alertPanel
        panel.orderFrontRegardless()
        
        panel.setFrame(
            NSRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height
            ),
            display: false
        )
        
        windowController = .init(window: panel)
    }
    
    private func deinitializeWindow() {
        guard let windowController else { return }
        windowController.close()
        self.windowController = nil
    }
}
