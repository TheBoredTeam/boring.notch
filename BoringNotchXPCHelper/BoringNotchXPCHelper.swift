//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import AppKit
import ApplicationServices
import CryptoKit
import IOKit
import Security

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {

    private static let maxAccessibilityElements = 10_000

    private weak var connection: NSXPCConnection?

    private let lunarStateQueue = DispatchQueue(label: "BoringNotchXPCHelper.lunar.state")
    private let lunarExecutableURL = URL(fileURLWithPath: "/Applications/Lunar.app/Contents/MacOS/Lunar")
    private var lunarProcess: Process?
    private var lunarPipeHandler: JSONLinesPipeHandler?
    private var lunarStreamTask: Task<Void, Never>?
    private var lunarListener: BoringNotchXPCHelperLunarListener?

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    override init() {
        super.init()
    }

    deinit {
        var processToTerminate: Process?
        var taskToCancel: Task<Void, Never>?
        var pipeHandlerToClose: JSONLinesPipeHandler?

        lunarStateQueue.sync {
            processToTerminate = self.lunarProcess
            self.lunarProcess = nil

            taskToCancel = self.lunarStreamTask
            self.lunarStreamTask = nil

            pipeHandlerToClose = self.lunarPipeHandler
            self.lunarPipeHandler = nil

            self.lunarListener = nil
        }

        taskToCancel?.cancel()
        if let p = processToTerminate, p.isRunning { p.terminate() }
        if let ph = pipeHandlerToClose {
            Task { await ph.close() }
        }
    }
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    @objc func codexPermissionPromptStatus(
        matchingChatTitle chatTitle: String,
        request: String,
        with reply: @escaping (Bool, Bool) -> Void
    ) {
        guard AXIsProcessTrusted() else {
            reply(false, false)
            return
        }
        reply(
            true,
            codexPermissionControls(
                matchingChatTitle: chatTitle,
                request: request
            ) != nil
        )
    }

    @objc func performCodexPermissionDecision(
        _ decision: String,
        matchingChatTitle chatTitle: String,
        request: String,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        guard AXIsProcessTrusted() else {
            reply(false, "Accessibility access is required to answer the Codex prompt from Boring Notch.")
            return
        }
        guard NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.openai.codex")
            .first != nil else {
            reply(false, "Codex is not running.")
            return
        }
        guard decision == "allow" || decision == "deny" else {
            reply(false, "The Codex permission decision is invalid.")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                reply(false, "The Codex permission response could not be verified.")
                return
            }
            guard let controls = self.waitForCodexPermissionControls(
                matchingChatTitle: chatTitle,
                request: request,
                timeout: 2
            ) else {
                reply(false, "The selected Codex permission prompt could not be matched.")
                return
            }

            let control = decision == "allow" ? controls.allow : controls.deny
            guard self.pressCodexPermissionControl(control) else {
                reply(false, "Codex did not accept the permission choice. Respond in Codex to continue.")
                return
            }

            if self.waitForCodexPermissionPromptToDisappear(
                matchingChatTitle: chatTitle,
                request: request,
                timeout: 0.5
            ) {
                reply(true, nil)
                return
            }

            // Chromium can report AXPress success without dispatching the
            // control's web event while its window is in the background.
            // Re-match the same chat/request, focus that exact accessibility
            // control, and post Return only to the Codex process. Keep Codex
            // in the background so this retry does not interrupt the user.
            guard let focusedControls = self.codexPermissionControls(
                matchingChatTitle: chatTitle,
                request: request
            ) else {
                reply(true, nil)
                return
            }
            let focusedControl = decision == "allow" ? focusedControls.allow : focusedControls.deny
            guard self.confirmCodexPermissionControl(focusedControl),
                  self.waitForCodexPermissionPromptToDisappear(
                      matchingChatTitle: chatTitle,
                      request: request,
                      timeout: 2
                  ) else {
                reply(false, "Codex did not accept the permission choice. Respond in Codex to continue.")
                return
            }
            reply(true, nil)
        }
    }

    private struct CodexPermissionControls {
        let allow: AXUIElement
        let deny: AXUIElement
    }

    private struct CodexPermissionScan {
        var text = ""
        var allowButtons: [AXUIElement] = []
        var denyButtons: [AXUIElement] = []
        var requestMatches: [CodexPermissionControls] = []
        var combinedMatches: [CodexPermissionControls] = []
        var promptCandidates: [CodexPermissionControls] = []
    }

    private func codexPermissionControls(
        matchingChatTitle chatTitle: String?,
        request: String?
    ) -> CodexPermissionControls? {
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.openai.codex")
            .first else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var windows = accessibilityElements(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        )
        let focusedWindow = accessibilityElements(
            of: applicationElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ).first
        if let focusedWindow {
            windows.removeAll(where: { CFHash($0) == CFHash(focusedWindow) })
            windows.insert(focusedWindow, at: 0)
        }

        let normalizedChatTitle = chatTitle.map(normalizedAccessibilityText)
        let normalizedRequest = request.map(normalizedAccessibilityText)
        var requestMatches: [CodexPermissionControls] = []
        var combinedMatches: [CodexPermissionControls] = []
        for window in windows {
            var visited = Set<CFHashCode>()
            var inspectedCount = 0
            let scan = scanCodexPermissionControls(
                in: window,
                matchingChatTitle: normalizedChatTitle,
                request: normalizedRequest,
                visited: &visited,
                inspectedCount: &inspectedCount
            )
            if let focusedWindow,
               CFHash(window) == CFHash(focusedWindow),
               let focusedMatch = resolvedPermissionControls(in: scan) {
                return focusedMatch
            }
            var windowPromptCandidates: [CodexPermissionControls] = []
            for candidate in scan.promptCandidates {
                appendUniquePermissionControls(candidate, to: &windowPromptCandidates)
            }
            if windowPromptCandidates.count == 1 {
                let onlyPrompt = windowPromptCandidates[0]
                if self.request(normalizedRequest, matches: scan.text) {
                    appendUniquePermissionControls(onlyPrompt, to: &requestMatches)
                }
                if self.request(normalizedChatTitle, matches: scan.text),
                   self.request(normalizedRequest, matches: scan.text) {
                    appendUniquePermissionControls(onlyPrompt, to: &combinedMatches)
                }
            }
            for match in scan.requestMatches {
                appendUniquePermissionControls(match, to: &requestMatches)
            }
            for match in scan.combinedMatches {
                appendUniquePermissionControls(match, to: &combinedMatches)
            }
        }
        if combinedMatches.count == 1 {
            return combinedMatches[0]
        }
        if requestMatches.count == 1 {
            return requestMatches[0]
        }
        return nil
    }

    private func resolvedPermissionControls(in scan: CodexPermissionScan) -> CodexPermissionControls? {
        for matches in [
            scan.combinedMatches,
            scan.requestMatches,
        ] {
            var uniqueMatches: [CodexPermissionControls] = []
            for match in matches {
                appendUniquePermissionControls(match, to: &uniqueMatches)
            }
            if uniqueMatches.count == 1 {
                return uniqueMatches[0]
            }
        }
        return nil
    }

    private func scanCodexPermissionControls(
        in element: AXUIElement,
        matchingChatTitle normalizedChatTitle: String?,
        request normalizedRequest: String?,
        visited: inout Set<CFHashCode>,
        inspectedCount: inout Int
    ) -> CodexPermissionScan {
        guard inspectedCount < Self.maxAccessibilityElements else {
            return CodexPermissionScan()
        }
        inspectedCount += 1
        let identity = CFHash(element)
        guard visited.insert(identity).inserted else { return CodexPermissionScan() }

        var scan = CodexPermissionScan()
        for child in accessibilityChildren(of: element) {
            let childScan = scanCodexPermissionControls(
                in: child,
                matchingChatTitle: normalizedChatTitle,
                request: normalizedRequest,
                visited: &visited,
                inspectedCount: &inspectedCount
            )
            for match in childScan.requestMatches {
                appendUniquePermissionControls(match, to: &scan.requestMatches)
            }
            for match in childScan.combinedMatches {
                appendUniquePermissionControls(match, to: &scan.combinedMatches)
            }
            for candidate in childScan.promptCandidates {
                appendUniquePermissionControls(candidate, to: &scan.promptCandidates)
            }
            scan.allowButtons.append(contentsOf: childScan.allowButtons)
            scan.denyButtons.append(contentsOf: childScan.denyButtons)
            appendAccessibilityText(childScan.text, to: &scan.text)
        }

        let elementLabel = accessibilityLabel(of: element)
        appendAccessibilityText(elementLabel, to: &scan.text)
        if isAccessibilityButtonActive(element) {
            let actionLabel = elementLabel.isEmpty && scan.text.split(separator: " ").count <= 4
                ? scan.text
                : elementLabel
            if isCodexAllowLabel(actionLabel) {
                scan.allowButtons.append(element)
            } else if isCodexDenyLabel(actionLabel) {
                scan.denyButtons.append(element)
            }
        }

        guard let pair = nearestPermissionPair(
            allowButtons: scan.allowButtons,
            denyButtons: scan.denyButtons
        ) else {
            return scan
        }
        appendUniquePermissionControls(pair, to: &scan.promptCandidates)
        let chatTitleMatches = request(normalizedChatTitle, matches: scan.text)
        let requestMatches = request(normalizedRequest, matches: scan.text)
        if requestMatches {
            appendUniquePermissionControls(pair, to: &scan.requestMatches)
        }
        if chatTitleMatches && requestMatches {
            appendUniquePermissionControls(pair, to: &scan.combinedMatches)
        }
        return scan
    }

    private func appendUniquePermissionControls(
        _ controls: CodexPermissionControls,
        to controlsList: inout [CodexPermissionControls]
    ) {
        guard !controlsList.contains(where: {
            CFHash($0.allow) == CFHash(controls.allow)
                && CFHash($0.deny) == CFHash(controls.deny)
        }) else {
            return
        }
        controlsList.append(controls)
    }

    private func nearestPermissionPair(
        allowButtons: [AXUIElement],
        denyButtons: [AXUIElement]
    ) -> CodexPermissionControls? {
        allowButtons.flatMap { allow in
            denyButtons.map { deny in
                (
                    controls: CodexPermissionControls(allow: allow, deny: deny),
                    distance: verticalDistance(between: allow, and: deny)
                )
            }
        }
        .min { $0.distance < $1.distance }?
        .controls
    }

    private func verticalDistance(
        between first: AXUIElement,
        and second: AXUIElement
    ) -> CGFloat {
        guard let firstPosition = accessibilityPoint(
            of: first,
            attribute: kAXPositionAttribute as CFString
        ), let secondPosition = accessibilityPoint(
            of: second,
            attribute: kAXPositionAttribute as CFString
        ) else {
            return .greatestFiniteMagnitude
        }
        return abs(firstPosition.y - secondPosition.y)
    }

    private func request(_ request: String?, matches text: String) -> Bool {
        guard let request, !request.isEmpty else { return false }
        let candidates = request.components(separatedBy: "\u{001F}")
        return candidates.contains { candidate in
            requestCandidate(candidate, matches: text)
        }
    }

    private func requestCandidate(_ candidate: String, matches text: String) -> Bool {
        let normalizedCandidate = normalizedAccessibilityText(candidate)
        let normalizedText = normalizedAccessibilityText(text)
        guard !normalizedCandidate.isEmpty, !normalizedText.isEmpty else { return false }
        return normalizedText.contains(normalizedCandidate)
    }

    private func appendAccessibilityText(_ value: String, to text: inout String) {
        guard !value.isEmpty, text.count < 32_000 else { return }
        if !text.isEmpty { text.append(" ") }
        text.append(contentsOf: value.prefix(32_000 - text.count))
    }

    private func normalizedAccessibilityText(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func isAccessibilityButtonActive(_ element: AXUIElement) -> Bool {
        guard let role = accessibilityString(
            of: element,
            attribute: kAXRoleAttribute as CFString
        ) else {
            return false
        }
        var actionNames: CFArray?
        let supportsPress = AXUIElementCopyActionNames(element, &actionNames) == .success
            && (actionNames as? [String])?.contains(kAXPressAction as String) == true
        guard supportsPress || [
            kAXButtonRole as String,
            "AXLink",
            "AXMenuButton",
            kAXRadioButtonRole as String,
        ].contains(role) else {
            return false
        }
        var enabledValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledValue
        ) == .success,
           let enabled = enabledValue as? Bool,
           !enabled {
            return false
        }
        return true
    }

    private func pressCodexPermissionControl(_ control: AXUIElement) -> Bool {
        AXUIElementPerformAction(control, kAXPressAction as CFString) == .success
    }

    private func confirmCodexPermissionControl(_ control: AXUIElement) -> Bool {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(control, &processIdentifier) == .success,
              processIdentifier > 0 else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            control,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        ) == .success else {
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 36,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 36,
                  keyDown: false
              ) else {
            return false
        }
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private func waitForCodexPermissionControls(
        matchingChatTitle chatTitle: String,
        request: String,
        timeout: TimeInterval
    ) -> CodexPermissionControls? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let controls = codexPermissionControls(
                matchingChatTitle: chatTitle,
                request: request
            ) {
                return controls
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return codexPermissionControls(
            matchingChatTitle: chatTitle,
            request: request
        )
    }

    private func waitForCodexPermissionPromptToDisappear(
        matchingChatTitle chatTitle: String,
        request: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if codexPermissionControls(
                matchingChatTitle: chatTitle,
                request: request
            ) == nil {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return codexPermissionControls(
            matchingChatTitle: chatTitle,
            request: request
        ) == nil
    }

    private func accessibilityPoint(
        of element: AXUIElement,
        attribute: CFString
    ) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(
            unsafeBitCast(value, to: AXValue.self),
            .cgPoint,
            &point
        ) else {
            return nil
        }
        return point
    }

    private func accessibilityElements(
        of element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else {
            return []
        }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [unsafeBitCast(value, to: AXUIElement.self)]
        }
        return value as? [AXUIElement] ?? []
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        var children = accessibilityElements(
            of: element,
            attribute: kAXVisibleChildrenAttribute as CFString
        )
        children.append(contentsOf: accessibilityElements(
            of: element,
            attribute: kAXChildrenAttribute as CFString
        ))
        children.append(contentsOf: accessibilityElements(
            of: element,
            attribute: kAXContentsAttribute as CFString
        ))

        var seen = Set<CFHashCode>()
        return children.filter { seen.insert(CFHash($0)).inserted }
    }

    private func accessibilityString(
        of element: AXUIElement,
        attribute: CFString
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func accessibilityLabel(of element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { accessibilityString(of: element, attribute: $0 as CFString) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isCodexAllowLabel(_ label: String) -> Bool {
        let normalized = normalizedAccessibilityLabel(label)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty, words.count <= 4 else { return false }
        guard !isCodexDenyLabel(normalized) else { return false }
        return words.contains("allow") || words.contains("approve")
    }

    private func isCodexDenyLabel(_ label: String) -> Bool {
        let normalized = normalizedAccessibilityLabel(label)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty, words.count <= 4 else { return false }
        return words.contains("deny")
            || words.contains("reject")
            || (words.contains("allow") && (words.contains("not") || words.contains("dont")))
    }

    private func normalizedAccessibilityLabel(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    private func brightnessDisplayID() -> CGDirectDisplayID {
        let mainDisplayID = CGMainDisplayID()
        var tmp: Float = 0

        if displayServicesGetBrightness(displayID: mainDisplayID, out: &tmp) || ioServiceFor(displayID: mainDisplayID) != nil {
            return mainDisplayID
        }

        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        let allocated = Int(count)
        var ids = [CGDirectDisplayID](repeating: 0, count: allocated)
        CGGetOnlineDisplayList(count, &ids, &count)
        for id in ids {
            if CGDisplayIsBuiltin(id) != 0 {
                return id
            }
        }

        return mainDisplayID
    }

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: displayID, out: &b) || ioServiceFor(displayID: displayID) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        if displayServicesGetBrightness(displayID: displayID, out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightness(displayID: displayID, value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }
    
    @objc func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightnessSmooth(displayID: displayID, value: value) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var ioCurrent: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &ioCurrent) == kIOReturnSuccess {
                let target = max(0, min(1, ioCurrent + value))
                let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, target) == kIOReturnSuccess
                IOObjectRelease(io)
                reply(ok)
                return
            }
            IOObjectRelease(io)
        }
        reply(false)
    }

    // MARK: - Lunar Events

    @objc func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let id = brightnessDisplayID()
        reply(NSNumber(value: id))
    }

    @objc func isLunarAvailable(with reply: @escaping (Bool) -> Void) {
        reply(FileManager.default.isExecutableFile(atPath: lunarExecutableURL.path))
    }

    @objc func startLunarEventStream(with reply: @escaping (Bool) -> Void) {
        lunarStateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                reply(true)
                return
            }

            guard FileManager.default.isExecutableFile(atPath: self.lunarExecutableURL.path) else {
                reply(false)
                return
            }

            guard let connection = self.connection else {
                reply(false)
                return
            }

            let listenerProxy = connection.remoteObjectProxyWithErrorHandler { _ in
                self.stopLunarEventStream()
            } as? BoringNotchXPCHelperLunarListener

            guard let listenerProxy else {
                reply(false)
                return
            }

            let process = Process()
            process.executableURL = self.lunarExecutableURL
            process.arguments = ["@", "listen", "--only-user-adjustments", "-j"]

            let pipeHandler = JSONLinesPipeHandler(decoder: JSONDecoder())
            process.standardOutput = pipeHandler.getPipe()
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { [weak self] _ in
                self?.stopLunarEventStream(reason: "Lunar stream ended")
            }

            do {
                try process.run()
            } catch {
                reply(false)
                return
            }

            self.lunarProcess = process
            self.lunarPipeHandler = pipeHandler
            self.lunarListener = listenerProxy

            let currentPipeHandler = pipeHandler
            self.lunarStreamTask = Task { [weak self] in
                await self?.readLunarEvents(pipeHandler: currentPipeHandler)
            }

            reply(true)
        }
    }

    @objc func stopLunarEventStream() {
        stopLunarEventStream(reason: nil)
    }

    private func stopLunarEventStream(reason: String?) {
        lunarStateQueue.async { [weak self] in
            guard let self else { return }

            self.lunarStreamTask?.cancel()
            self.lunarStreamTask = nil

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                lunarProcess.terminate()
            }

            self.lunarProcess = nil

            if let pipeHandler = self.lunarPipeHandler {
                Task { await pipeHandler.close() }
            }

            self.lunarPipeHandler = nil

            if let reason {
                self.lunarListener?.lunarStreamDidStop(reason)
            }

            self.lunarListener = nil
        }
    }

    private func readLunarEvents(pipeHandler: JSONLinesPipeHandler) async {
        await pipeHandler.readJSONLines(as: LunarBrightnessEvent.self) { [weak self] event in
            self?.emitLunarEvent(event)
        }
    }

    private func emitLunarEvent(_ event: LunarBrightnessEvent) {
        let payload = BNLunarBrightnessEvent(
            brightness: event.brightness,
            display: event.display
        )
        lunarStateQueue.async { [weak self] in
            self?.lunarListener?.lunarEventDidUpdate(payload)
        }
    }

    // MARK: - Lunar OSD preference (hideOSD)

    private static let lunarBundleID = "fyi.lunar.Lunar"
    private static let lunarHideOSDKey = "hideOSD"

    @objc func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void) {
        let appID = Self.lunarBundleID as CFString
        let key = Self.lunarHideOSDKey as CFString
        let value = hide as CFBoolean
        NSLog("Hide OSD in Lunar: \(hide)")
        CFPreferencesSetValue(key, value, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let ok = CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        reply(ok)
    }

    // MARK: - Codex Notifications

    private static let codexHookEvents = ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop"]
    private static let codexHookMarker = "boring-notch-notify.py"
    private static let codexHookSecretMarker = "boring-notch-notify.secret"
    private static let maximumCodexPayloadBytes = 256 * 1024
    private static let maximumEncodedCodexPayloadCharacters = (
        (maximumCodexPayloadBytes + 2) / 3
    ) * 4
    private static let codexPayloadMaximumAge: TimeInterval = 120
    private static let codexNotificationScript = #"""
    import base64
    import hashlib
    import hmac
    import json
    import os
    import secrets
    import subprocess
    import sys
    import time

    MAX_PAYLOAD_BYTES = 256 * 1024
    MAX_PROMPT_CHARACTERS = 16_000
    MAX_DESCRIPTION_CHARACTERS = 16_000
    MAX_COMMAND_CHARACTERS = 96_000
    MAX_ADDITIONAL_INPUT_CHARACTERS = 64_000

    def short(value, limit=4000):
        if not isinstance(value, str):
            return value
        return value[:limit]

    def bounded_tool_input(value):
        if not isinstance(value, dict):
            return None

        bounded = {}
        description = value.get("description")
        if isinstance(description, str):
            bounded["description"] = short(description, MAX_DESCRIPTION_CHARACTERS)

        command = value.get("command")
        if isinstance(command, str):
            bounded["command"] = short(command, MAX_COMMAND_CHARACTERS)

        additional = {
            key: item
            for key, item in value.items()
            if key not in ("description", "command")
        }
        if additional:
            rendered = json.dumps(additional, separators=(",", ":"), ensure_ascii=False)
            if len(rendered) <= MAX_ADDITIONAL_INPUT_CHARACTERS:
                bounded.update(additional)
            else:
                bounded["additional_input"] = short(
                    rendered,
                    MAX_ADDITIONAL_INPUT_CHARACTERS,
                )
        return bounded

    def thread_metadata(session_id):
        metadata = {"chat_title": "Untitled chat"}
        if not isinstance(session_id, str) or not session_id:
            return metadata

        codex_home = os.path.dirname(os.path.abspath(__file__))
        try:
            with open(
                os.path.join(codex_home, "session_index.jsonl"),
                "r",
                encoding="utf-8",
            ) as index:
                for line in index:
                    try:
                        entry = json.loads(line)
                    except (TypeError, ValueError):
                        continue
                    if entry.get("id") != session_id:
                        continue
                    title = entry.get("thread_name")
                    if isinstance(title, str) and title.strip():
                        metadata["chat_title"] = short(title.strip(), 240)
        except (FileNotFoundError, OSError, UnicodeError):
            pass

        try:
            with open(
                os.path.join(codex_home, ".codex-global-state.json"),
                "r",
                encoding="utf-8",
            ) as state_file:
                state = json.load(state_file)

            projectless = state.get("projectless-thread-ids", [])
            if session_id in projectless:
                metadata["project_name"] = "No project"
                return metadata

            assignment = state.get("thread-project-assignments", {}).get(session_id)
            if isinstance(assignment, dict) and assignment.get("projectKind") == "local":
                project = state.get("local-projects", {}).get(assignment.get("projectId"))
                if isinstance(project, dict):
                    project_name = project.get("name")
                    if isinstance(project_name, str) and project_name.strip():
                        metadata["project_name"] = short(project_name.strip(), 240)
        except (FileNotFoundError, OSError, TypeError, ValueError, UnicodeError):
            pass
        return metadata

    def open_notch(payload):
        payload["boring_notch_auth"] = {
            "timestamp": time.time(),
            "nonce": secrets.token_hex(16),
        }
        serialized = json.dumps(
            payload,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
        if len(serialized) > MAX_PAYLOAD_BYTES:
            return False

        encoded = base64.urlsafe_b64encode(
            serialized
        ).decode("ascii").rstrip("=")
        secret_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "boring-notch-notify.secret",
        )
        try:
            with open(secret_path, "rb") as secret_file:
                secret = secret_file.read()
        except OSError:
            return False
        if len(secret) != 32:
            return False

        signature = base64.urlsafe_b64encode(
            hmac.new(
                secret,
                encoded.encode("ascii"),
                hashlib.sha256,
            ).digest()
        ).decode("ascii").rstrip("=")
        result = subprocess.run(
            [
                "/usr/bin/open",
                "-g",
                "boringnotch://codex-event?payload=" + encoded + "&signature=" + signature,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
        return result.returncode == 0

    def mirror_permission_request(payload):
        payload["boring_notch_approval"] = {
            "control": "accessibility",
        }
        open_notch(payload)

    try:
        source = json.load(sys.stdin)
        payload = {}
        for key in ("hook_event_name", "session_id", "turn_id", "cwd", "tool_name", "last_assistant_message", "error", "message", "status"):
            if key in source:
                payload[key] = short(source[key])
        if "prompt" in source:
            payload["prompt"] = short(source["prompt"], MAX_PROMPT_CHARACTERS)
        payload.update(thread_metadata(source.get("session_id")))
        tool_input = bounded_tool_input(source.get("tool_input"))
        if tool_input is not None:
            payload["tool_input"] = tool_input
        if source.get("hook_event_name") == "PermissionRequest":
            mirror_permission_request(payload)
            print("{}")
        else:
            open_notch(payload)
            print("{}")
    except Exception:
        print("{}")
    """#

    @objc func validateCodexNotificationPayload(
        _ payload: String,
        signature: String,
        with reply: @escaping (Bool) -> Void
    ) {
        guard !payload.isEmpty,
              payload.count <= Self.maximumEncodedCodexPayloadCharacters,
              signature.count == 43,
              let signatureData = decodeBase64URL(signature),
              signatureData.count == SHA256.byteCount else {
            reply(false)
            return
        }

        do {
            let secret = try Data(contentsOf: codexHookURLs().secret)
            guard secret.count == 32 else {
                reply(false)
                return
            }
            let key = SymmetricKey(data: secret)
            guard HMAC<SHA256>.isValidAuthenticationCode(
                signatureData,
                authenticating: Data(payload.utf8),
                using: key
            ), let decodedPayload = decodeBase64URL(payload),
               let object = try JSONSerialization.jsonObject(with: decodedPayload) as? [String: Any],
               let authentication = object["boring_notch_auth"] as? [String: Any],
               let timestamp = authentication["timestamp"] as? TimeInterval,
               let nonce = authentication["nonce"] as? String,
               nonce.count == 32,
               Date().timeIntervalSince1970 - timestamp >= -5,
               Date().timeIntervalSince1970 - timestamp <= Self.codexPayloadMaximumAge else {
                reply(false)
                return
            }
            reply(true)
        } catch {
            reply(false)
        }
    }

    @objc func isCodexNotificationHookInstalled(with reply: @escaping (Bool) -> Void) {
        do {
            let urls = codexHookURLs()
            guard FileManager.default.fileExists(atPath: urls.script.path) else {
                reply(false)
                return
            }
            guard try Data(contentsOf: urls.script) == Data(Self.codexNotificationScript.utf8) else {
                reply(false)
                return
            }
            guard try Data(contentsOf: urls.secret).count == 32 else {
                reply(false)
                return
            }
            let root = try readCodexHookConfiguration(at: urls.configuration)
            reply(Self.codexHookEvents.allSatisfy {
                containsCurrentOwnedCodexHook(
                    in: root,
                    event: $0,
                    scriptURL: urls.script
                )
            })
        } catch {
            reply(false)
        }
    }

    @objc func setCodexNotificationHookInstalled(
        _ installed: Bool,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            let urls = codexHookURLs()
            try FileManager.default.createDirectory(
                at: urls.configuration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var root = try readCodexHookConfiguration(at: urls.configuration)
            var hooks: [String: Any]
            if let existingHooks = root["hooks"] {
                guard let typedHooks = existingHooks as? [String: Any] else {
                    throw codexHookConfigurationError(
                        code: 4,
                        message: "Codex hooks.json has an invalid hooks object."
                    )
                }
                hooks = typedHooks
            } else {
                hooks = [:]
            }

            for event in Self.codexHookEvents {
                var groups: [[String: Any]]
                if let existingGroups = hooks[event] {
                    guard let typedGroups = existingGroups as? [[String: Any]] else {
                        throw codexHookConfigurationError(
                            code: 5,
                            message: "Codex hooks.json has invalid \(event) hooks."
                        )
                    }
                    groups = typedGroups
                } else {
                    groups = []
                }
                groups.removeAll(where: isOwnedCodexHookGroup)
                if installed {
                    let isPermissionRequest = event == "PermissionRequest"
                    var handler: [String: Any] = [
                        "type": "command",
                        "command": codexHookCommand(scriptURL: urls.script),
                        "timeout": 5,
                    ]
                    if isPermissionRequest {
                        handler["async"] = true
                    }
                    groups.append(["hooks": [handler]])
                }
                hooks[event] = groups
            }

            root["hooks"] = hooks
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            if installed {
                _ = try ensureCodexHookSecret(at: urls.secret)
                try Data(Self.codexNotificationScript.utf8).write(to: urls.script, options: .atomic)
            }
            try data.write(to: urls.configuration, options: .atomic)

            if !installed {
                for url in [urls.script, urls.secret]
                    where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func codexHookURLs() -> (configuration: URL, script: URL, secret: URL) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        return (
            directory.appendingPathComponent("hooks.json"),
            directory.appendingPathComponent(Self.codexHookMarker),
            directory.appendingPathComponent(Self.codexHookSecretMarker)
        )
    }

    private func ensureCodexHookSecret(at url: URL) throws -> Data {
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            guard existing.count == 32 else {
                throw NSError(
                    domain: "BoringNotch.CodexHooks",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The Codex hook secret is invalid. Disconnect and reconnect Codex."]
                )
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError(
                domain: "BoringNotch.CodexHooks",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "A secure Codex hook secret could not be generated."]
            )
        }
        let secret = Data(bytes)
        try secret.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return secret
    }

    private func decodeBase64URL(_ encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private func readCodexHookConfiguration(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let root = object as? [String: Any] else {
            throw codexHookConfigurationError(
                code: 1,
                message: "Codex hooks.json must contain a JSON object."
            )
        }
        return root
    }

    private func containsCurrentOwnedCodexHook(
        in root: [String: Any],
        event: String,
        scriptURL: URL
    ) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return false }
        let ownedGroups = groups.filter(isOwnedCodexHookGroup)
        guard ownedGroups.count == 1,
              let handlers = ownedGroups[0]["hooks"] as? [[String: Any]],
              handlers.count == 1 else { return false }

        let handler = handlers[0]
        let expectedTimeout = 5
        let expectedAsync = event == "PermissionRequest"
        return handler["type"] as? String == "command"
            && handler["command"] as? String == codexHookCommand(scriptURL: scriptURL)
            && handler["timeout"] as? Int == expectedTimeout
            && (handler["async"] as? Bool ?? false) == expectedAsync
    }

    private func isOwnedCodexHookGroup(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            (handler["command"] as? String)?.contains(Self.codexHookMarker) == true
        }
    }

    private func codexHookCommand(scriptURL: URL) -> String {
        let quotedPath = scriptURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "/usr/bin/python3 '\(quotedPath)'"
    }

    private func codexHookConfigurationError(code: Int, message: String) -> NSError {
        NSError(
            domain: "BoringNotch.CodexHooks",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }
    
    private func displayServicesSetBrightnessSmooth(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightnessSmooth") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

// MARK: - Lunar Parsing

private struct LunarBrightnessEvent: Decodable {
    let brightness: Double
    let display: Int

    init(from decoder: NSCoder) {
        display = decoder.decodeInteger(forKey: "display")
        brightness = decoder.decodeDouble(forKey: "brightness")
    }
}

private actor JSONLinesPipeHandler {
    nonisolated let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        let pipe = Pipe()
        self.pipe = pipe
        self.fileHandle = pipe.fileHandleForReading
        self.decoder = decoder
    }

    nonisolated func getPipe() -> Pipe {
        return pipe
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async {
        do {
            try await processLines(as: type) { decodedObject in
                onLine(decodedObject)
            }
        } catch {
            // Ignore stream errors to keep the helper lightweight.
        }
    }

    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) -> Void) {
        guard let data = line.data(using: .utf8) else { return }
        if let decodedObject = try? decoder.decode(T.self, from: data) {
            onLine(decodedObject)
        }
    }

    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil

            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            // Ignore close errors.
        }
    }
}
