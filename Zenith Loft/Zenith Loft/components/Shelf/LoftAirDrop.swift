import Cocoa

class LoftAirDrop: NSObject, NSSharingServiceDelegate {
    let files: [URL]
    
    init(files: [URL]) {
        self.files = files
        super.init()
    }
    
    func begin() {
        do {
            try sendEx(files)
        } catch {
            NSAlert.popError(error)
        }
    }
    
    private func sendEx(_ files: [URL]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            throw NSError(domain: "LoftAirDrop", code: 1, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("AirDrop service not available", comment: ""),
            ])
        }
        guard service.canPerform(withItems: files) else {
            throw NSError(domain: "LoftAirDrop", code: 2, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("AirDrop service not available", comment: ""),
            ])
        }
        service.delegate = self
        service.perform(withItems: files)
    }
}
