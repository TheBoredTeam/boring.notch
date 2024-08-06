import Foundation
import Combine
import SwiftUI

struct DownloadEvent: Identifiable {
    let id = UUID()
    let path: String
    let eventFlags: FSEventStreamEventFlags
    let eventID: FSEventStreamEventId
    let timestamp: Date
    var progress: Double = 0.0
}

class ObservingClass: NSObject, ObservableObject, NSFilePresenter {
    var presentedItemURL: URL?
    var snapshotPath: String?
    
    lazy var presentedItemOperationQueue: OperationQueue = .main
    @Published var recentFiles: [String] = []
    
    override init() {
        super.init()
        self.presentedItemURL = URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        print(NSHomeDirectory())
        // Set the URL to the Downloads folder
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            self.presentedItemURL = downloadsURL
            NSFileCoordinator.addFilePresenter(self)
        }
    }
    
    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }
    
    private func presentedSubitemDidChangeAtURL(url: NSURL) {
        refreshFiles()
    }

     func presentedItemDidChange() {
        refreshFiles()
    }
    
    func refreshFiles() {
        print("refreshFiles")
        guard let path = snapshotPath else { return }
        
        var isDirectory: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            do {
                let list = try FileManager.default.contentsOfDirectory(atPath: path)
                DispatchQueue.main.async {
                    self.recentFiles = list
                }
            } catch {
                // Error handling
                print("Error reading contents of directory: \(error)")
            }
        }
    }
}


struct DownloadView: View {
    @StateObject private var observingClass = ObservingClass()
    
    var body: some View {
        VStack {
            Text("Monitoring User Folder")
                .font(.headline)
            
            VStack {
                Text("Monitoring User Downloads Folder")
                    .font(.headline)
                
                List(observingClass.recentFiles, id: \.self) { file in
                    Text(file)
                }
            }
            .padding()
            .onAppear {
                print("sOME SHIT IS HAPPENING HERE")
                // Set the snapshot path to the desired directory i want to monitor downloads folder
                observingClass.snapshotPath = observingClass.presentedItemURL?.path
                observingClass.refreshFiles()
            }
        }
        .padding()
    }
}


#Preview {
    DownloadView()
}
