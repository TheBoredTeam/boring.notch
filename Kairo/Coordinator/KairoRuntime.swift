import Foundation

func kairoDebug(_ msg: String) {
    let line = "[Kairo] \(msg)\n"
    fputs(line, stderr)
    if let data = line.data(using: .utf8) {
        let logPath = FileManager.default.temporaryDirectory.appendingPathComponent("kairo_debug.log").path
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

@MainActor
final class KairoRuntime {
    static let shared = KairoRuntime()
    private init() {}

    var coordinator: OrbCoordinator?

    var orbieController: OrbieController? {
        coordinator?.orbieController
    }

    func present(_ viewID: OrbieViewID, payload: AnyHashable? = nil) {
        Task {
            await coordinator?.present(viewID, payload: payload)
        }
    }

    func presentAndWait(_ viewID: OrbieViewID, payload: AnyHashable? = nil) async {
        await coordinator?.present(viewID, payload: payload)
    }

    func dismiss() {
        coordinator?.orbieController.hide()
    }
}
