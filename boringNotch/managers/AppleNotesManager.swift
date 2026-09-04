//
//  AppleNotesManager.swift
//  boringNotch
//

import Defaults
import Foundation

struct AppleNote: Identifiable, Equatable {
    let id: String
    let title: String
    let plaintext: String
    let accountName: String
    let creationDate: Date
    let modificationDate: Date
    let colorIndex: Int
    let isPinned: Bool
    let isManagedByBoringNotch: Bool
}

enum AppleNotesPayloadParser {
    static let fieldSeparator = "\u{001F}"
    static let recordSeparator = "\u{001E}"

    static func parse(
        _ payload: String,
        managedIDs: Set<String>,
        pinnedIDs: Set<String> = [],
        colorOverrides: [String: Int] = [:]
    ) -> [AppleNote] {
        guard !payload.isEmpty else { return [] }

        var uniqueNotes: [String: AppleNote] = [:]

        for record in payload.split(separator: Character(recordSeparator), omittingEmptySubsequences: true) {
            let fields = record.split(
                separator: Character(fieldSeparator),
                maxSplits: 5,
                omittingEmptySubsequences: false
            )
            guard fields.count == 6 else { continue }

            let id = String(fields[0])
            guard !id.isEmpty else { continue }

            let title = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let creationDate = parseAppleScriptSeconds(String(fields[2])) ?? .distantPast
            let modificationDate = parseAppleScriptSeconds(String(fields[3])) ?? creationDate
            let colorIndex = min(max(colorOverrides[id] ?? 0, 0), 5)
            uniqueNotes[id] = AppleNote(
                id: id,
                title: title.isEmpty ? String(localized: "Untitled Note") : title,
                plaintext: String(fields[4]),
                accountName: String(fields[5]),
                creationDate: creationDate,
                modificationDate: modificationDate,
                colorIndex: colorIndex,
                isPinned: pinnedIDs.contains(id),
                isManagedByBoringNotch: managedIDs.contains(id)
            )
        }

        return uniqueNotes.values.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func parseAppleScriptSeconds(_ raw: String) -> Date? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "E+", with: "e")
        guard let seconds = Double(normalized) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

enum AppleNotesError: LocalizedError {
    case automationDenied
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return String(
                localized:
                    "Apple Notes access is unavailable. Allow Boring Notch to control Notes in System Settings > Privacy & Security > Automation."
            )
        case .scriptFailed(let message):
            return message
        }
    }
}

@MainActor
final class AppleNotesManager: ObservableObject {
    static let shared = AppleNotesManager()

    @Published private(set) var notes: [AppleNote] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private static let folderName = "Boring Notch"

    private init() {}

    func refresh() async {
        guard !isSyncing else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let output = try await runScriptReturningString(fetchScript, allowingEmpty: true)
            let parsedNotes = AppleNotesPayloadParser.parse(
                output,
                managedIDs: Set(Defaults[.managedAppleNoteIDs]),
                pinnedIDs: Set(Defaults[.pinnedAppleNoteIDs]),
                colorOverrides: Defaults[.appleNoteColorOverrides]
            )
            notes = Defaults[.showAppleNotesContent]
                ? parsedNotes
                : parsedNotes.filter(\.isManagedByBoringNotch)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createManagedNote(title: String, plaintext: String, colorIndex: Int) async -> AppleNote? {
        do {
            let newID = try await runScriptReturningString(createScript(title: title, plaintext: plaintext))
            var managedIDs = Set(Defaults[.managedAppleNoteIDs])
            managedIDs.insert(newID)
            Defaults[.managedAppleNoteIDs] = Array(managedIDs).sorted()
            setColorIndex(colorIndex, for: newID)
            await refresh()
            return notes.first(where: { $0.id == newID })
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateManagedNote(id: String, title: String, plaintext: String) async -> Bool {
        guard isManaged(id) else { return false }

        do {
            try await runScriptVoid(updateScript(id: id, title: title, plaintext: plaintext))
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteManagedNote(id: String) async -> Bool {
        guard isManaged(id) else { return false }

        do {
            try await runScriptVoid(deleteScript(id: id))
            var managedIDs = Set(Defaults[.managedAppleNoteIDs])
            managedIDs.remove(id)
            Defaults[.managedAppleNoteIDs] = Array(managedIDs).sorted()
            var pinnedIDs = Set(Defaults[.pinnedAppleNoteIDs])
            pinnedIDs.remove(id)
            Defaults[.pinnedAppleNoteIDs] = Array(pinnedIDs).sorted()
            var colorOverrides = Defaults[.appleNoteColorOverrides]
            colorOverrides.removeValue(forKey: id)
            Defaults[.appleNoteColorOverrides] = colorOverrides
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func revealInNotes(id: String) async {
        do {
            try await runScriptVoid(revealScript(id: id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func togglePin(for id: String) {
        var pinnedIDs = Set(Defaults[.pinnedAppleNoteIDs])
        if pinnedIDs.contains(id) {
            pinnedIDs.remove(id)
        } else {
            pinnedIDs.insert(id)
        }
        Defaults[.pinnedAppleNoteIDs] = Array(pinnedIDs).sorted()
        refreshPresentationMetadata()
    }

    func setColorIndex(_ colorIndex: Int, for id: String) {
        var overrides = Defaults[.appleNoteColorOverrides]
        overrides[id] = min(max(colorIndex, 0), 5)
        Defaults[.appleNoteColorOverrides] = overrides
        refreshPresentationMetadata()
    }

    private func isManaged(_ id: String) -> Bool {
        Defaults[.managedAppleNoteIDs].contains(id)
    }

    private func refreshPresentationMetadata() {
        let pinnedIDs = Set(Defaults[.pinnedAppleNoteIDs])
        let colorOverrides = Defaults[.appleNoteColorOverrides]
        notes = notes.map { note in
            AppleNote(
                id: note.id,
                title: note.title,
                plaintext: note.plaintext,
                accountName: note.accountName,
                creationDate: note.creationDate,
                modificationDate: note.modificationDate,
                colorIndex: min(max(colorOverrides[note.id] ?? 0, 0), 5),
                isPinned: pinnedIDs.contains(note.id),
                isManagedByBoringNotch: note.isManagedByBoringNotch
            )
        }
        notes.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var fetchScript: String {
        """
        set fieldSep to character id 31
        set recordSep to character id 30
        set chunks to {}
        tell application "Notes"
            set epoch to (current date)
            set hours of epoch to 0
            set minutes of epoch to 0
            set seconds of epoch to 0
            set year of epoch to 1970
            set month of epoch to January
            set day of epoch to 1
            repeat with accountRef in every account
                set accountName to name of accountRef
                repeat with noteRef in every note of accountRef
                    if password protected of noteRef is false then
                        set noteID to my sanitizeField(id of noteRef, fieldSep, recordSep)
                        set noteName to my sanitizeField(name of noteRef, fieldSep, recordSep)
                        set createdSeconds to my sanitizeField(((creation date of noteRef) - epoch) as string, fieldSep, recordSep)
                        set modifiedSeconds to my sanitizeField(((modification date of noteRef) - epoch) as string, fieldSep, recordSep)
                        set noteText to my sanitizeField(plaintext of noteRef, fieldSep, recordSep)
                        set sourceAccount to my sanitizeField(accountName, fieldSep, recordSep)
                        set end of chunks to noteID & fieldSep & noteName & fieldSep & createdSeconds & fieldSep & modifiedSeconds & fieldSep & noteText & fieldSep & sourceAccount
                    end if
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to recordSep
        return chunks as text

        on sanitizeField(valueToSanitize, fieldSep, recordSep)
            set AppleScript's text item delimiters to fieldSep
            set fieldParts to text items of valueToSanitize
            set AppleScript's text item delimiters to " "
            set sanitizedValue to fieldParts as text
            set AppleScript's text item delimiters to recordSep
            set recordParts to text items of sanitizedValue
            set AppleScript's text item delimiters to " "
            return recordParts as text
        end sanitizeField
        """
    }

    private func createScript(title: String, plaintext: String) -> String {
        let escapedTitle = appleScriptEscape(sanitizedTitle(title))
        let escapedBody = appleScriptEscape(htmlBody(for: plaintext))
        let escapedFolder = appleScriptEscape(Self.folderName)

        return """
        tell application "Notes"
            try
                set syncFolder to folder "\(escapedFolder)" of default account
            on error
                set syncFolder to make new folder at default account with properties {name:"\(escapedFolder)"}
            end try
            set createdNote to make new note at syncFolder with properties {name:"\(escapedTitle)", body:"\(escapedBody)"}
            return id of createdNote
        end tell
        """
    }

    private func updateScript(id: String, title: String, plaintext: String) -> String {
        let escapedID = appleScriptEscape(id)
        let escapedTitle = appleScriptEscape(sanitizedTitle(title))
        let escapedBody = appleScriptEscape(htmlBody(for: plaintext))

        return """
        tell application "Notes"
            set targetNote to first note whose id is "\(escapedID)"
            set name of targetNote to "\(escapedTitle)"
            set body of targetNote to "\(escapedBody)"
        end tell
        """
    }

    private func deleteScript(id: String) -> String {
        let escapedID = appleScriptEscape(id)

        return """
        tell application "Notes"
            set matchingNotes to every note whose id is "\(escapedID)"
            if (count of matchingNotes) > 0 then
                delete item 1 of matchingNotes
            end if
        end tell
        """
    }

    private func revealScript(id: String) -> String {
        let escapedID = appleScriptEscape(id)

        return """
        tell application "Notes"
            set targetNote to first note whose id is "\(escapedID)"
            show targetNote
            activate
        end tell
        """
    }

    private func sanitizedTitle(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? String(localized: "Untitled Note") : normalized
    }

    private func htmlBody(for plaintext: String) -> String {
        let escaped = plaintext
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        return escaped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.isEmpty ? "<div><br></div>" : "<div>\(line)</div>"
            }
            .joined()
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func runScriptReturningString(_ script: String, allowingEmpty: Bool = false) async throws -> String {
        let descriptor = try await executeScript(script)
        guard let value = descriptor.stringValue, allowingEmpty || !value.isEmpty else {
            throw AppleNotesError.scriptFailed(String(localized: "Notes returned an empty response."))
        }
        return value
    }

    private func runScriptVoid(_ script: String) async throws {
        _ = try await executeScript(script)
    }

    private func executeScript(_ script: String) async throws -> NSAppleEventDescriptor {
        do {
            guard let descriptor = try await AppleScriptHelper.execute(script) else {
                throw AppleNotesError.scriptFailed(String(localized: "Notes script returned no result."))
            }
            return descriptor
        } catch let error as NSError {
            if error.domain == "AppleScriptError",
               (error.userInfo["NSAppleScriptErrorNumber"] as? Int) == -1743 {
                throw AppleNotesError.automationDenied
            }

            let message = (error.userInfo["NSAppleScriptErrorMessage"] as? String)
                ?? error.localizedDescription
            throw AppleNotesError.scriptFailed(message)
        }
    }
}
