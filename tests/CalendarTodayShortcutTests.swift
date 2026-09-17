//
//  CalendarTodayShortcutTests.swift
//  boringNotch
//
//  Focused calendar regression checks.
//

import AppKit

@MainActor
private final class TestPanel: NSPanel, CalendarKeyboardFocusProviding {
    var wantsKeyForTextInput = false
    var calendarOwners: Set<ObjectIdentifier> = []
    func setCalendarFocus(_ requested: Bool, owner: AnyObject) {
        if requested { calendarOwners.insert(ObjectIdentifier(owner)) }
        else { calendarOwners.remove(ObjectIdentifier(owner)) }
        if calendarOwners.isEmpty && !wantsKeyForTextInput { resignKey() }
    }
    var keyForTest = true
    var keyClaims = 0
    override var isKeyWindow: Bool { keyForTest }
    override func makeKey() { keyForTest = true; keyClaims += 1 }
    override func resignKey() { keyForTest = false }
}

private final class InteractionEvent: NSEvent {
    let target: NSWindow
    let kind: NSEvent.EventType
    override var window: NSWindow? { target }
    override var type: NSEvent.EventType { kind }

    init(window: NSWindow, type: NSEvent.EventType) {
        target = window
        kind = type
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@main
struct CalendarTodayShortcutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = TestPanel(contentRect: .init(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let other = TestPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        var checks = 0
        func event(_ text: String = "t", flags: NSEvent.ModifierFlags = [], window: NSWindow? = nil,
                   type: NSEvent.EventType = .keyDown, repeated: Bool = false, keyCode: UInt16 = 17) -> NSEvent {
            guard let result = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: (window ?? panel).windowNumber, context: nil,
                             characters: text, charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: keyCode) else {
                fatalError("Missing keyboard event fixture")
            }
            return result
        }
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        expect(CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Plain T returns to today")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("T", flags: .shift), in: panel), "Uppercase T is supported")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("T", flags: .capsLock), in: panel), "Caps Lock does not change the shortcut")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("е", keyCode: 17), in: panel), "Physical T works with the Russian layout")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event("е", keyCode: 14), in: panel), "The same foreign letter on another physical key is unaffected")
        expect(CalendarTodayShortcutRouting.shouldHandle(event("t", keyCode: 14), in: panel), "Literal T is supported on alternate keyboard layouts")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event("е", flags: .command, keyCode: 17), in: panel), "Physical T preserves modified shortcuts")
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, .function, [.command, .shift]] {
            expect(!CalendarTodayShortcutRouting.shouldHandle(event(flags: flags), in: panel), "Modified shortcuts keep their original actions")
        }
        expect(!CalendarTodayShortcutRouting.shouldHandle(event("x", keyCode: 7), in: panel), "Other letters are unaffected")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(type: .keyUp), in: panel), "Key up does not repeat the action")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(window: other), in: panel), "Other windows are unaffected")
        panel.keyForTest = false
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "A background calendar does not capture typing")
        panel.keyForTest = true
        let editor = NSTextView(frame: .init(x: 0, y: 0, width: 100, height: 50))
        panel.contentView?.addSubview(editor)
        editor.isEditable = true
        panel.makeFirstResponder(editor)
        expect(!CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Typing T in editable text is preserved")
        expect(!CalendarTodayShortcutRouting.shouldHandle(event("е", keyCode: 17), in: panel), "Typing with the Russian layout in editable text is preserved")
        editor.isEditable = false
        expect(CalendarTodayShortcutRouting.shouldHandle(event(), in: panel), "Selectable event details still allow Today")

        var actions = 0
        let handler = CalendarTodayKeyView { actions += 1 }
        panel.contentView?.addSubview(handler)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        panel.makeFirstResponder(nil)
        let interactions: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        for type in interactions {
            panel.keyForTest = false
            let claims = panel.keyClaims
            let previousActions = actions
            let interaction = InteractionEvent(window: panel, type: type)
            expect(handler.handleLocalEvent(interaction) === interaction, "Calendar interactions reach their original controls")
            expect(panel.isKeyWindow && panel.keyClaims == claims + 1, "Calendar interaction recovers lost key status")
            expect(panel.firstResponder === handler, "Calendar interaction restores its responder")
            expect(actions == previousActions, "Interaction does not invoke Today")
            expect(handler.handleLocalEvent(event()) == nil && actions == previousActions + 1, "T works after focus recovery")
            expect(handler.handleLocalEvent(event(repeated: true)) == nil && actions == previousActions + 1, "Held T does not repeat Today")
        }

        let beforeRussianKey = actions
        expect(handler.handleLocalEvent(event("е", keyCode: 17)) == nil && actions == beforeRussianKey + 1,
               "A physical T event invokes Today after interaction recovery in the Russian layout")

        // Reproduce a Clipboard field editor lingering after its tab disappears.
        editor.isEditable = true
        editor.isFieldEditor = true
        panel.makeFirstResponder(editor)
        let claims = panel.keyClaims
        let previousActions = actions
        let click = InteractionEvent(window: panel, type: .leftMouseDown)
        expect(handler.handleLocalEvent(event()) != nil && actions == previousActions, "T alone preserves text editing")
        expect(handler.handleLocalEvent(click) === click, "A calendar click is forwarded after Clipboard")
        expect(panel.firstResponder === handler && panel.keyClaims == claims, "A key panel still replaces the stale Clipboard editor")
        expect(handler.handleLocalEvent(event()) == nil && actions == previousActions + 1, "T works after clearing the stale editor")

        editor.isEditable = false
        panel.makeFirstResponder(editor)
        panel.keyForTest = false
        let wheel = InteractionEvent(window: panel, type: .scrollWheel)
        let beforeSelection = actions
        expect(handler.handleLocalEvent(wheel) === wheel, "Scrolling selectable details is forwarded")
        expect(panel.isKeyWindow && panel.firstResponder === editor, "Read-only text keeps its selection responder")
        expect(actions == beforeSelection, "Scrolling selected text does not invoke Today")
        expect(handler.handleLocalEvent(event()) == nil && actions == beforeSelection + 1, "Selected text still supports Today")

        panel.keyForTest = false
        let beforeOtherWindow = actions
        let claimsBeforeOtherWindow = panel.keyClaims
        for type in interactions {
            let interaction = InteractionEvent(window: other, type: type)
            expect(handler.handleLocalEvent(interaction) === interaction, "Other-window interactions are forwarded")
        }
        let otherKey = event(window: other)
        expect(handler.handleLocalEvent(otherKey) === otherKey, "Other-window typing is forwarded")
        expect(!panel.isKeyWindow && panel.keyClaims == claimsBeforeOtherWindow && actions == beforeOtherWindow,
               "Other-window events cannot claim focus or invoke Today")
        let unfocusedKey = event()
        expect(handler.handleLocalEvent(unfocusedKey) === unfocusedKey && !panel.isKeyWindow,
               "Keyboard input alone never takes focus from another application")

        panel.wantsKeyForTextInput = true
        editor.isEditable = true
        panel.makeFirstResponder(editor)
        panel.keyForTest = true
        let beforeReply = actions
        let replyClick = InteractionEvent(window: panel, type: .leftMouseDown)
        expect(handler.handleLocalEvent(replyClick) === replyClick, "Notification reply clicks remain available")
        expect(panel.firstResponder === editor, "Calendar never replaces an active notification reply editor")
        expect(handler.handleLocalEvent(event()) != nil && actions == beforeReply, "Typing T in a notification reply does not invoke Today")
        panel.makeFirstResponder(handler)
        expect(handler.handleLocalEvent(event()) != nil && actions == beforeReply,
               "Notification reply focus blocks Today before its editor becomes first responder")
        panel.makeFirstResponder(editor)
        expect(panel.calendarOwners.contains(ObjectIdentifier(handler)), "The calendar owns a scoped key-focus request")
        handler.removeMonitor()
        expect(panel.calendarOwners.isEmpty && panel.wantsKeyForTextInput && panel.isKeyWindow,
               "Calendar teardown releases only its focus request and preserves notification reply key access")
        panel.wantsKeyForTextInput = false
        panel.keyForTest = false
        expect(handler.handleLocalEvent(click) === click && !panel.isKeyWindow, "A dismantled calendar cannot reclaim focus")
        expect(handler.handleLocalEvent(event()) != nil && actions == beforeOtherWindow, "A dismantled calendar cannot invoke Today")
        print("PASS \(checks) scoped calendar Today shortcut checks")
    }
}
