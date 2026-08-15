//
//  ContactAvatarManager.swift
//  boringNotch
//
//  Resolves a notification sender's name to a Contacts photo, for the
//  "person, not app" avatar treatment iMessage's Communication Notifications
//  use. Notification Center banners don't expose a photo over Accessibility
//  at all (verified against live WhatsApp/Discord banners — title/subtitle/
//  body text and buttons only, no image element), so this is the only way
//  to get one for third-party apps too.
//
//  Many senders won't resolve — a WhatsApp/Telegram display name rarely
//  matches a Contacts card exactly, and some notifications aren't from a
//  person at all. Callers fall back to a monogram avatar in that case.
//

import AppKit
import Contacts
import SwiftUI

@MainActor
final class ContactAvatarManager: ObservableObject {
    static let shared = ContactAvatarManager()

    private let store = CNContactStore()
    private var isAuthorized = false
    /// Exact-name lookups are cheap to repeat but the store fetch isn't;
    /// misses are remembered too so a name that doesn't resolve isn't
    /// retried forever. NSCache lets the system evict hits under pressure.
    private let cache = NSCache<NSString, NSImage>()
    private var knownMisses: Set<String> = []

    private init() {
        isAuthorized = CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    private func ensureAuthorized() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            isAuthorized = granted
            return granted
        default:
            return false
        }
    }

    /// Looks up a contact photo by exact display-name match. Returns nil
    /// immediately (no permission prompt) unless the caller has already
    /// established access via `requestAccessIfNeeded`.
    func photo(forSenderNamed name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        if knownMisses.contains(name) { return nil }
        guard isAuthorized else { return nil }

        let keys = [CNContactImageDataKey, CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: name)

        guard let contacts = try? store.unifiedContacts(matching: predicate, keysToFetch: keys),
              // Ambiguous matches (multiple people share a first name) are
              // worse than no photo — a wrong face is worse than a monogram.
              contacts.count == 1,
              let data = contacts[0].thumbnailImageData ?? contacts[0].imageData,
              let image = NSImage(data: data)
        else {
            NSLog("[boringNotch] avatar for \(name.debugDescription): no contact photo, using monogram")
            knownMisses.insert(name)
            return nil
        }

        NSLog("[boringNotch] avatar for \(name.debugDescription): using contact photo")
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Phone number for a contact, digits only and international, suitable
    /// for a whatsapp:// deep link — or nil when it can't be resolved
    /// *confidently*.
    ///
    /// The bar is deliberately high, because the cost of being wrong is
    /// dropping someone's private reply into a stranger's chat:
    ///
    ///  - exactly one matching contact, else the name is ambiguous
    ///  - the stored number must already carry a country code (leading "+").
    ///    A local-format number can't be made international without guessing
    ///    the country, and a wrong guess is a wrong person.
    ///
    /// Group chats resolve to nothing here, which is correct — a group name
    /// isn't a contact and has no single number to send to.
    func phoneNumber(forContactNamed name: String) -> String? {
        guard isAuthorized else { return nil }

        let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        guard let contacts = try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: name),
            keysToFetch: keys
        ), contacts.count == 1 else { return nil }

        // Prefer an explicitly mobile number; a landline won't reach
        // WhatsApp at all.
        let numbers = contacts[0].phoneNumbers
        let preferred = numbers.first {
            $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone
        } ?? numbers.first

        guard let raw = preferred?.value.stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+") else { return nil }

        let digits = trimmed.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    /// Call once, e.g. when notification live activity starts, so the first
    /// banner isn't blocked on a permission prompt mid-render.
    func requestAccessIfNeeded() async {
        _ = await ensureAuthorized()
    }
}

/// Stable "person" avatar: a real contact photo when one resolves, otherwise
/// a colored monogram — the same fallback Contacts/Messages/Mail use for
/// people without a saved photo, so it never looks broken.
struct PersonAvatarView: View {
    let name: String
    let size: CGFloat

    @ObservedObject private var contacts = ContactAvatarManager.shared

    var body: some View {
        Group {
            if let photo = contacts.photo(forSenderNamed: name) {
                Image(nsImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    monogramColor
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// Hashes the name to a hue so the same person gets the same color across
    /// notifications, without needing to persist anything.
    private var monogramColor: Color {
        var hasher = Hasher()
        hasher.combine(name)
        let hue = Double(abs(hasher.finalize()) % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}
