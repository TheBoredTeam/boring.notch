// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Darwin
import Foundation

/// Expands developer ZIPs without handing archive paths to a filesystem extractor.
/// Only regular files and directories are written, with bounded streaming reads.
enum ExtensionArchive {
    struct PreparedPackage: Sendable {
        let url: URL
        fileprivate let temporaryRoot: URL?

        func cleanup() {
            if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        }
    }

    static func withPreparedPackage<T>(at source: URL, _ body: (URL) throws -> T) throws -> T {
        let package = try prepare(source)
        defer { package.cleanup() }
        return try body(package.url)
    }

    /// Call off the main actor, then retain the result until installation finishes.
    /// The caller owns security-scoped access to the original chosen URL.
    static func prepare(_ source: URL) throws -> PreparedPackage {
        if source.pathExtension.lowercased() == "bnplugin" {
            return PreparedPackage(url: source, temporaryRoot: nil)
        }
        guard source.pathExtension.lowercased() == "zip" else { throw ExtensionError.invalidArchive }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0 else { throw ExtensionError.invalidArchive }
        guard size <= ExtensionPackage.maximumBytes else { throw ExtensionError.archiveTooLarge }
        try validateDirectoryBounds(source, fileSize: size)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "boring-notch-extension-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        do {
            try extract(source, to: root)
            let roots = try FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey]).filter {
                    $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store"
                }
            guard roots.count == 1, let package = roots.first,
                  package.pathExtension == "bnplugin" else { throw ExtensionError.invalidArchive }
            _ = try ExtensionPackage.inspect(package)
            return PreparedPackage(url: package, temporaryRoot: root)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private static func validateDirectoryBounds(_ source: URL, fileSize: Int) throws {
        // Read only ZIP's bounded end record before libarchive can allocate its
        // central directory. Split/ZIP64 archives are unnecessary at our limits.
        guard fileSize >= 22 else { throw ExtensionError.invalidArchive }
        let file = try FileHandle(forReadingFrom: source)
        defer { try? file.close() }
        let tailSize = min(fileSize, 65_557)
        try file.seek(toOffset: UInt64(fileSize - tailSize))
        guard let tail = try file.read(upToCount: tailSize), tail.count == tailSize else {
            throw ExtensionError.invalidArchive
        }
        func number(_ offset: Int, _ width: Int) -> UInt64 {
            (0..<width).reduce(0) { $0 | UInt64(tail[offset + $1]) << (8 * $1) }
        }
        guard let record = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            number($0, 4) == 0x06054b50 && $0 + 22 + Int(number($0 + 20, 2)) == tail.count
        }) else { throw ExtensionError.invalidArchive }
        let count = number(record + 10, 2)
        guard number(record + 4, 2) == 0, number(record + 6, 2) == 0,
              number(record + 8, 2) == count, count > 0 else { throw ExtensionError.invalidArchive }
        guard count <= ExtensionPackage.maximumEntries else { throw ExtensionError.archiveTooLarge }
        let length = number(record + 12, 4)
        let offset = number(record + 16, 4)
        guard length >= count * 46,
              offset + length == UInt64(fileSize - tailSize + record) else {
            throw ExtensionError.invalidArchive
        }
    }

    private static func extract(_ source: URL, to root: URL) throws {
        let api = try ArchiveReaderAPI()
        guard let reader = api.create() else { throw ExtensionError.invalidArchive }
        defer { _ = api.free(reader) }
        guard api.supportZIP(reader) == 0, api.supportNoFilter(reader) == 0,
              source.withUnsafeFileSystemRepresentation({ path in
                  path.map { api.open(reader, $0, 65_536) } ?? -1
              }) == 0 else { throw ExtensionError.invalidArchive }

        var entries = 0
        var bytes = 0
        var declaredBytes: Int64 = 0
        var paths = Set<String>()
        var spellings: [String: String] = [:]
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            var entry: OpaquePointer?
            let status = api.next(reader, &entry)
            if status == 1 { break } // ARCHIVE_EOF
            // Warnings are rejected too: install only an entirely valid archive.
            guard status == 0, let entry, let rawPath = api.path(entry),
                  let path = String(validatingUTF8: rawPath),
                  api.symlink(entry) == nil, api.hardlink(entry) == nil,
                  api.encrypted(entry) == 0 else { throw ExtensionError.invalidArchive }
            entries += 1
            guard entries <= ExtensionPackage.maximumEntries else { throw ExtensionError.archiveTooLarge }
            let components = try validatedComponents(path)
            let relativePath = components.joined(separator: "/")
            let key = relativePath.precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(key).inserted else { throw ExtensionError.invalidArchive }
            // A case-sensitive archive must not merge distinct parent paths
            // when extracted onto the usual case-insensitive macOS volume.
            for depth in 1...components.count {
                let prefix = components.prefix(depth).joined(separator: "/")
                let normalized = prefix.precomposedStringWithCanonicalMapping.lowercased()
                guard spellings[normalized].map({ $0 == prefix }) ?? true else {
                    throw ExtensionError.invalidArchive
                }
                spellings[normalized] = prefix
            }

            let kind = api.filetype(entry)
            let isDirectory = kind == 0o040000
            guard isDirectory || kind == 0o100000 else { throw ExtensionError.invalidArchive }
            let declared = api.size(entry)
            guard declared >= 0 else { throw ExtensionError.invalidArchive }
            guard declared <= Int64(ExtensionPackage.maximumBytes) - declaredBytes else {
                throw ExtensionError.archiveTooLarge
            }
            declaredBytes += declared
            let destination = root.appendingPathComponent(relativePath, isDirectory: isDirectory)
            // Finder/ditto may place AppleDouble sidecars beside bundle files
            // (not only in __MACOSX). They are transport metadata, and writing
            // them as ordinary resources invalidates the signed resource seal.
            let isMetadata = components.contains { $0 == "__MACOSX" || $0.hasPrefix("._") }
                || components.last == ".DS_Store"
            if isDirectory {
                guard declared == 0 else { throw ExtensionError.invalidArchive }
                if !isMetadata {
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true,
                                                           attributes: [.posixPermissions: 0o700])
                }
            } else {
                var file: FileHandle?
                if !isMetadata {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    // O_EXCL also rejects aliases created implicitly as parents.
                    let descriptor = destination.withUnsafeFileSystemRepresentation { path in
                        path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) } ?? -1
                    }
                    guard descriptor >= 0 else { throw ExtensionError.invalidArchive }
                    file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                }
                defer { try? file?.close() }
                var fileBytes: Int64 = 0
                while true {
                    let read = buffer.withUnsafeMutableBytes { api.read(reader, $0.baseAddress, $0.count) }
                    guard read >= 0 else { throw ExtensionError.invalidArchive }
                    if read == 0 { break }
                    guard read <= ExtensionPackage.maximumBytes - bytes else { throw ExtensionError.archiveTooLarge }
                    bytes += read
                    fileBytes += Int64(read)
                    guard fileBytes <= declared else { throw ExtensionError.invalidArchive }
                    try file?.write(contentsOf: Data(buffer.prefix(read)))
                }
                guard fileBytes == declared else { throw ExtensionError.invalidArchive }
                // Only ordinary executable permission is preserved, never setuid/setgid.
                let permissions = api.permissions(entry) & 0o111 == 0 ? 0o600 : 0o700
                if let file, fchmod(file.fileDescriptor, mode_t(permissions)) != 0 {
                    throw ExtensionError.invalidArchive
                }
            }
        }
        guard entries > 0 else { throw ExtensionError.invalidArchive }
    }

    private static func validatedComponents(_ path: String) throws -> [String] {
        guard !path.isEmpty, path.utf8.count <= 1_024, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ExtensionError.invalidArchive
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let names = components.last?.isEmpty == true ? components.dropLast() : components[...]
        guard !names.isEmpty, names.count <= 32,
              names.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw ExtensionError.invalidArchive
        }
        return names.map(String.init)
    }
}

/// Stable C API from the macOS SDK's system libarchive. Dynamic lookup keeps
/// this narrowly scoped ZIP reader independent of Swift packages and app ABI.
private final class ArchiveReaderAPI {
    typealias Create = @convention(c) () -> OpaquePointer?
    typealias Unary = @convention(c) (OpaquePointer) -> Int32
    typealias Open = @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int) -> Int32
    typealias Next = @convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    typealias StringValue = @convention(c) (OpaquePointer) -> UnsafePointer<CChar>?
    typealias Int64Value = @convention(c) (OpaquePointer) -> Int64
    typealias ModeValue = @convention(c) (OpaquePointer) -> UInt16
    typealias Read = @convention(c) (OpaquePointer, UnsafeMutableRawPointer?, Int) -> Int

    private let library: UnsafeMutableRawPointer
    let create: Create
    let free: Unary
    let supportZIP: Unary
    let supportNoFilter: Unary
    let open: Open
    let next: Next
    let path: StringValue
    let symlink: StringValue
    let hardlink: StringValue
    let encrypted: Unary
    let filetype: ModeValue
    let permissions: ModeValue
    let size: Int64Value
    let read: Read

    init() throws {
        guard let library = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else {
            throw ExtensionError.invalidArchive
        }
        self.library = library
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let address = dlsym(library, name) else { throw ExtensionError.invalidArchive }
            return unsafeBitCast(address, to: T.self)
        }
        do {
            create = try symbol("archive_read_new", Create.self)
            free = try symbol("archive_read_free", Unary.self)
            supportZIP = try symbol("archive_read_support_format_zip", Unary.self)
            supportNoFilter = try symbol("archive_read_support_filter_none", Unary.self)
            open = try symbol("archive_read_open_filename", Open.self)
            next = try symbol("archive_read_next_header", Next.self)
            path = try symbol("archive_entry_pathname", StringValue.self)
            symlink = try symbol("archive_entry_symlink", StringValue.self)
            hardlink = try symbol("archive_entry_hardlink", StringValue.self)
            encrypted = try symbol("archive_entry_is_encrypted", Unary.self)
            filetype = try symbol("archive_entry_filetype", ModeValue.self)
            permissions = try symbol("archive_entry_perm", ModeValue.self)
            size = try symbol("archive_entry_size", Int64Value.self)
            read = try symbol("archive_read_data", Read.self)
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit { dlclose(library) }
}
