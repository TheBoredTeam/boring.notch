//
//  DistractionBlocker.swift
//  boringNotch
//
//  Keeps distracting apps and sites out of the way while a focus session runs.
//
//  What a sandboxed app can honestly do here is limited, and the design says
//  so rather than pretending otherwise:
//
//  * Apps are *hidden*, not killed or prevented from launching. Hiding is
//    reversible, loses no work, and needs no privileges — the user can always
//    bring the app back, which is the right amount of friction for a focus
//    aid rather than a parental control.
//  * Sites are handled per *tab*, by asking the front browser what it is
//    showing and navigating that tab away. Real network-level blocking needs
//    either root (to edit /etc/hosts) or a Network Extension, neither of
//    which this app has or should have.
//
//  Both are advisory. Nothing here is a security boundary, and the settings
//  pane says as much.
//

import AppKit
import Combine
import Foundation

@MainActor
final class DistractionBlocker: ObservableObject {
    static let shared = DistractionBlocker()

    /// Whether blocking is currently enforced.
    @Published private(set) var isActive = false
    /// How many times something was pushed aside this session — the number
    /// the focus panel reports back to the user.
    @Published private(set) var interruptionsBlocked = 0
    /// Name of the most recent thing blocked, for the notch nudge.
    @Published private(set) var lastBlocked: String?

    /// Browsers whose active tab this app knows how to read, and how.
    ///
    /// Firefox is deliberately absent: it exposes no AppleScript dictionary
    /// for the active tab's URL, so there is no way to read or redirect it.
    /// The settings pane names it rather than silently doing nothing.
    private enum BrowserScripting {
        case safari(appName: String)
        case chromium(appName: String)

        var appName: String {
            switch self {
            case .safari(let name), .chromium(let name): return name
            }
        }

        /// AppleScript that returns the front tab's URL, or "" if there is none.
        var readURLScript: String {
            switch self {
            case .safari(let name):
                return """
                tell application "\(name)"
                    if (count of windows) is 0 then return ""
                    return URL of front document
                end tell
                """
            case .chromium(let name):
                return """
                tell application "\(name)"
                    if (count of windows) is 0 then return ""
                    return URL of active tab of front window
                end tell
                """
            }
        }

        func navigateAwayScript(to destination: String) -> String {
            switch self {
            case .safari(let name):
                return """
                tell application "\(name)"
                    if (count of windows) is 0 then return
                    set URL of front document to "\(destination)"
                end tell
                """
            case .chromium(let name):
                return """
                tell application "\(name)"
                    if (count of windows) is 0 then return
                    set URL of active tab of front window to "\(destination)"
                end tell
                """
            }
        }

        static func forBundleID(_ bundleID: String) -> BrowserScripting? {
            switch normalizeBundleIdentifier(bundleID).lowercased() {
            case "com.apple.safari": return .safari(appName: "Safari")
            case "com.apple.safaritechnologypreview": return .safari(appName: "Safari Technology Preview")
            case "com.google.chrome": return .chromium(appName: "Google Chrome")
            case "com.google.chrome.canary": return .chromium(appName: "Google Chrome Canary")
            case "com.microsoft.edgemac": return .chromium(appName: "Microsoft Edge")
            case "com.brave.browser": return .chromium(appName: "Brave Browser")
            case "com.vivaldi.vivaldi": return .chromium(appName: "Vivaldi")
            case "com.operasoftware.opera": return .chromium(appName: "Opera")
            default: return nil
            }
        }
    }

    /// Where a blocked tab is sent. `about:blank` rather than a custom page:
    /// a sandboxed app's container is unreadable to the browser, so any local
    /// HTML we wrote would fail to load and leave the user on an error page.
    private static let blockedDestination = "about:blank"

    private var blocklist = DistractionBlocklist()
    private var activationObserver: NSObjectProtocol?
    private var sitePollTask: Task<Void, Never>?

    /// Tabs are polled rather than observed — there is no notification for
    /// "the front tab changed". Two seconds is responsive enough to catch a
    /// detour without making an Apple Event round-trip every frame.
    private static let sitePollInterval: Duration = .seconds(2)

    private init() {}

    // MARK: - Lifecycle

    func start(with blocklist: DistractionBlocklist) {
        self.blocklist = blocklist
        guard !blocklist.isEmpty else {
            stop()
            return
        }

        isActive = true
        interruptionsBlocked = 0
        lastBlocked = nil

        startObservingAppActivation()
        startPollingSites()
    }

    /// Applies a changed blocklist without resetting the session's counters —
    /// the user ticking one more site mid-session should not zero the
    /// "interruptions blocked" tally they have been watching.
    func update(with blocklist: DistractionBlocklist) {
        guard isActive else { return }
        self.blocklist = blocklist

        if blocklist.isEmpty {
            stop()
            return
        }
        startObservingAppActivation()
        startPollingSites()
    }

    func stop() {
        isActive = false
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        sitePollTask?.cancel()
        sitePollTask = nil
    }

    // MARK: - Apps

    private func startObservingAppActivation() {
        guard blocklist.blockApps, !blocklist.apps.isEmpty else {
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
                self.activationObserver = nil
            }
            return
        }
        guard activationObserver == nil else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleActivation(of: app)
            }
        }
    }

    private func handleActivation(of app: NSRunningApplication) {
        guard isActive, let bundleID = app.bundleIdentifier else { return }
        // Never act on ourselves: hiding the notch app while it is showing the
        // countdown would be self-defeating.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        guard blocklist.shouldBlockApp(bundleID: bundleID) else { return }

        // Hide rather than terminate. `hide()` is reversible and loses no
        // work; the user can bring the app straight back if they meant it.
        if app.hide() {
            record(app.localizedName ?? bundleID)
        }
    }

    // MARK: - Sites

    private func startPollingSites() {
        guard blocklist.blockSites, !blocklist.sites.isEmpty else {
            sitePollTask?.cancel()
            sitePollTask = nil
            return
        }
        guard sitePollTask == nil else { return }

        sitePollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkFrontmostTab()
                try? await Task.sleep(for: DistractionBlocker.sitePollInterval)
            }
        }
    }

    private func checkFrontmostTab() async {
        guard isActive, blocklist.blockSites else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier,
              let browser = BrowserScripting.forBundleID(bundleID)
        else { return }

        guard let urlString = await runScript(browser.readURLScript), !urlString.isEmpty else { return }
        guard blocklist.shouldBlockSite(urlString: urlString) else { return }

        _ = await runScript(browser.navigateAwayScript(to: Self.blockedDestination))
        record(URL(string: urlString)?.host ?? urlString)
    }

    /// Runs a script and returns its string result.
    ///
    /// Failures are swallowed on purpose and logged at debug: the usual cause
    /// is the user not having granted Automation access for that browser yet,
    /// and a focus timer is not the place to throw an alert every two seconds.
    /// The settings pane explains the permission instead.
    private func runScript(_ source: String) async -> String? {
        do {
            let descriptor = try await AppleScriptHelper.execute(source)
            return descriptor?.stringValue
        } catch {
            Log.general.debug("Focus site check failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Reporting

    private func record(_ name: String) {
        interruptionsBlocked += 1
        lastBlocked = name
        Log.general.debug("Focus blocked \(name)")
    }
}
