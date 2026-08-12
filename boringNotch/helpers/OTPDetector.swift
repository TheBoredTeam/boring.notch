//
//  OTPDetector.swift
//  boringNotch
//
//  Finds a one-time verification code in notification text. Precision over
//  recall: a phone number or price shown as a fake "code to copy" is worse
//  than occasionally missing a real one — same trade-off iOS's own OTP
//  autofill makes (it also requires contextual signal, not bare digits).
//
//  Rules, in order:
//   1. A digit run of 4–8 digits (or two 3-digit groups joined by a dash/
//      space, e.g. "123-456") is a *candidate*.
//   2. A candidate is only accepted if a verification-related keyword
//      ("code", "otp", "verification", "passcode", "pin", …) appears within
//      `keywordWindow` characters of it — this is what keeps "call me at
//      9876543210" and "invoice #48293021" from matching, since neither has
//      a keyword nearby, without needing hand-written phone/invoice rules.
//   3. Currency, percentage, and time-adjacent digits are rejected outright
//      even if a keyword happens to be nearby (e.g. "OTP fee is $500").
//   4. If no digit-only candidate is accepted, a secondary pass looks for a
//      short uppercase alphanumeric token (Steam Guard-style: "R7K9P2") next
//      to the same keyword set.
//

import Foundation

enum OTPDetector {
    /// Longest a real OTP/2FA code gets in practice; wider misses ambiguity
    /// with tracking numbers and account IDs.
    private static let digitCountRange = 4...8

    /// How close a keyword has to be to a candidate to count as context,
    /// measured in UTF-16 code units. Covers "Your code is 482910" and
    /// "482910 is your verification code" without also matching a keyword
    /// three sentences away.
    private static let keywordWindow = 40

    private static let keywords = [
        "verification", "one-time", "one time", "passcode", "otp",
        "security code", "confirmation code", "confirmation", "access code",
        "auth code", "authentication code", "two-factor", "2fa", "pin", "code"
    ]

    /// Used for the alphanumeric fallback only. Excludes bare "code"/"pin" —
    /// those two are common in non-OTP contexts too ("promo code SAVE20",
    /// "pin your location"), which is fine for the digit-only pass (a random
    /// 6-digit number near "code" is almost always a real OTP) but would
    /// wrongly accept a dictionary-word promo code like "SAVE20" here.
    private static let strongKeywords = [
        "verification", "one-time", "one time", "passcode", "otp",
        "security code", "confirmation code", "access code", "auth code",
        "authentication code", "two-factor", "2fa"
    ]

    private static let digitRunRegex = try! NSRegularExpression(
        pattern: #"\d{3}[-\s]\d{3}\b|\b\d{4,8}\b"#
    )
    private static let alphanumericRegex = try! NSRegularExpression(
        pattern: #"\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{5,8}\b"#
    )

    /// Returns the code with any separators stripped, ready to paste into an
    /// OTP field — or nil if nothing in `text` clears the bar above.
    static func detect(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let ns = text as NSString

        if let match = bestDigitCandidate(in: text, ns: ns) {
            return match.replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: " ", with: "")
        }

        return bestAlphanumericCandidate(in: text, ns: ns)
    }

    private static func bestDigitCandidate(in text: String, ns: NSString) -> String? {
        let matches = digitRunRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard !isExcluded(match.range, in: ns), hasNearbyKeyword(match.range, in: ns) else { continue }
            return ns.substring(with: match.range)
        }
        return nil
    }

    private static func bestAlphanumericCandidate(in text: String, ns: NSString) -> String? {
        let matches = alphanumericRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches where hasNearbyKeyword(match.range, in: ns, from: strongKeywords) {
            return ns.substring(with: match.range)
        }
        return nil
    }

    /// Currency amounts, percentages, and clock times shouldn't match even
    /// with a keyword nearby ("OTP delivery fee is $500", "meeting at 4:30").
    private static func isExcluded(_ range: NSRange, in ns: NSString) -> Bool {
        let before = charBefore(range, in: ns)
        let after = charAfter(range, in: ns)

        if let before, "$€£¥₹".contains(before) { return true }
        if let after, after == "%" { return true }
        if let after, after == ":" { return true }
        if let before, before == ":" { return true }
        if let after, after == "." {
            // "500.00" — a decimal amount, not a code with a trailing period.
            let next = ns.substring(with: NSRange(location: range.location + range.length, length: min(3, ns.length - range.location - range.length)))
            if next.dropFirst().allSatisfy(\.isNumber) { return true }
        }
        return false
    }

    private static func charBefore(_ range: NSRange, in ns: NSString) -> Character? {
        guard range.location > 0 else { return nil }
        return Character(UnicodeScalar(ns.character(at: range.location - 1))!)
    }

    private static func charAfter(_ range: NSRange, in ns: NSString) -> Character? {
        let end = range.location + range.length
        guard end < ns.length else { return nil }
        return Character(UnicodeScalar(ns.character(at: end))!)
    }

    private static func hasNearbyKeyword(_ range: NSRange, in ns: NSString, from list: [String] = keywords) -> Bool {
        let windowStart = max(0, range.location - keywordWindow)
        let windowEnd = min(ns.length, range.location + range.length + keywordWindow)
        let window = ns.substring(with: NSRange(location: windowStart, length: windowEnd - windowStart)).lowercased()
        return list.contains { window.contains($0) }
    }
}

#if DEBUG
/// Non-exhaustive but covers the shapes that matter: separators, prefix vs.
/// suffix keyword position, currency/time/percentage traps, and an
/// alphanumeric fallback. Run via `OTPDetector.runSelfCheck()`.
extension OTPDetector {
    static func runSelfCheck() {
        let shouldDetect: [(String, String)] = [
            ("Your WhatsApp code: 123-456. Don't share this with anyone.", "123456"),
            ("G-593821 is your Google verification code.", "593821"),
            ("Your Instagram code is 482910. Learn more.", "482910"),
            ("Use 7482 as your verification code. Expires in 10 minutes.", "7482"),
            ("123456 is your Facebook confirmation code", "123456"),
            ("<#> Your ABC App code is 384950 #hash", "384950"),
            ("Your OTP for a transaction of INR 500.00 is 837201. Valid for 5 mins.", "837201"),
            ("Your Amazon OTP is: 4821", "4821"),
            ("Your Steam Guard verification code: R7K9P2", "R7K9P2")
        ]

        let shouldMiss: [String] = [
            "Hey, call me at 9876543210 when you're free",
            "Meeting at 3:30 today, don't forget code review at 4",
            "Your invoice #48293021 total is due",
            "Ref: 293847, please quote when calling about your 2023 order",
            "Get 20% off with code SAVE20 at checkout",
            "The OTP delivery fee is $5000 this month"
        ]

        for (text, expected) in shouldDetect {
            let got = detect(in: text)
            assert(got == expected, "OTPDetector missed \"\(text)\" — expected \(expected), got \(got ?? "nil")")
        }
        for text in shouldMiss {
            let got = detect(in: text)
            assert(got == nil, "OTPDetector false-positived on \"\(text)\" — got \(got ?? "nil")")
        }
    }
}
#endif
