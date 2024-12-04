import Cocoa
 import SwiftUI
// Add this at the top of the file
extension Notification.Name {
    static let serviceFilesReceived = Notification.Name("serviceFilesReceived")
}

class MosaicServiceHandler: NSObject {
    @objc func generateMosaic(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = pboard.pasteboardItems else { return }
        
        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                urls.append(url)
            }
        }
        
        if !urls.isEmpty {
            // Create a new window with its own view model
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
           
            
            let contentView = ContentView()
            window.contentView = NSHostingView(rootView: contentView)
            
            // Update the view model with the dropped files
            DispatchQueue.main.async {
                if urls.count == 1 {
                    let url = urls[0]
                    contentView.viewModel.inputPaths = [(url.path, 0)]
                    
                    if url.hasDirectoryPath {
                        contentView.viewModel.inputType = .folder
                    } else if url.pathExtension.lowercased() == "m3u8" {
                        contentView.viewModel.inputType = .m3u8
                    } else {
                        contentView.viewModel.inputType = .files
                    }
                } else {
                    contentView.viewModel.inputPaths = urls.map { ($0.path, 0) }
                    contentView.viewModel.inputType = .files
                }
            }
            
            window.makeKeyAndOrderFront(nil)
            window.center()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
