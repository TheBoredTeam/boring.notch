import AppKit

func getAttributedString(content: Any, type: NSPasteboard.PasteboardType) -> NSAttributedString? {
    if let stringContent = content as? String {
        return NSAttributedString(string: stringContent)
    }
    if type == .rtf, let data = content as? Data {
        return NSAttributedString(rtf: data, documentAttributes: nil)
    } else if type == .html, let data = content as? Data {
        return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
    } else if type.rawValue == "public.utf8-plain-text", let data = content as? Data {
        return try? NSAttributedString(data: data, documentAttributes: nil)
    } else if type == .string {
        return NSAttributedString(string: content as? String ?? "")
    } else if type == .fileURL {
        return NSAttributedString(string: content as? String ?? "")
    } else if type == NSPasteboard.PasteboardType("com.apple.webarchive"), let data = content as? Data {
        return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.webArchive], documentAttributes: nil)
    }
    return nil
}

func isText(type: NSPasteboard.PasteboardType) -> Bool {
    return type == .string || type == .html || type == .rtf || type == .html || type == .string || type.rawValue == "public.utf8-plain-text" || type.rawValue == "public.utf16-external-plain-text" || type.rawValue == "com.apple.webarchive"
}
