//
//  Ext+FileProvider.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    private func duplicateToOurStorage(_ url: URL?) throws -> URL? {
        guard let url else { return nil }
        let temp = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.createDirectory(
            at: temp.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: url, to: temp)
        return temp
    }

    func convertToFilePathThatIsWhatWeThinkItWillWorkWithNotchDrop() -> URL? {
        var url: URL?
        let sem = DispatchSemaphore(value: 0)
        _ = loadObject(ofClass: URL.self) { item, _ in
            url = try? self.duplicateToOurStorage(item)
            sem.signal()
        }
        sem.wait()
        if url == nil {
            loadInPlaceFileRepresentation(
                forTypeIdentifier: UTType.data.identifier
            ) { input, _, _ in
                defer { sem.signal() }
                url = try? self.duplicateToOurStorage(input)
            }
            sem.wait()
        }
        return url
    }
}

extension [NSItemProvider] {
    func interfaceConvert() -> [URL]? {
        let urls = compactMap { provider -> URL? in
            provider.convertToFilePathThatIsWhatWeThinkItWillWorkWithNotchDrop()
        }
        guard urls.count == count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAlert.popError(NSLocalizedString("One or more files failed to load", comment: ""))
            }
            return nil
        }
        return urls
    }
}
