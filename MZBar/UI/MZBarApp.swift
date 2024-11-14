import SwiftUI
import UniformTypeIdentifiers

@main
struct MZBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
/*        Settings {
            EmptyView()
        }*/
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var statusItem: NSStatusItem?
     
     // Reference to view model to handle drops
     private var viewModel: MosaicViewModel?
     
     func applicationDidFinishLaunching(_ notification: Notification) {
         // Create the status bar item
         statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
         
         if let statusButton = statusItem?.button {
             statusButton.image = NSImage(systemSymbolName: "mosaic", accessibilityDescription: "MosaicGen")
             statusButton.action = #selector(toggleWindow)
         }
         
         // Register services
         //NSApp.servicesProvider = MosaicServiceHandler()
         
         // Set activation policy to regular app
         NSApp.setActivationPolicy(.regular)
         
         // Set up dock drag and drop
       
     }
     
     private func setupDockDragAndDrop() {
         // Register for drag and drop types
         let types: [NSPasteboard.PasteboardType] = [
             .fileURL,
             .URL,
             NSPasteboard.PasteboardType("public.movie"),
             NSPasteboard.PasteboardType("public.video")
         ]
         
         NSApp.dockTile.showsApplicationBadge = true
         
      
         
         // Register as a drag and drop destination
    
         
         // Create a custom dock tile view if needed
       
     }
     
     // Handle files dropped on dock icon
     func application(_ application: NSApplication, open urls: [URL]) {
         handleDroppedFiles(urls)
     }
     
     // Handle files dropped on app icon in Finder
     func application(_ application: NSApplication, openFiles filenames: [String]) {
         let urls = filenames.map { URL(fileURLWithPath: $0) }
         handleDroppedFiles(urls)
     }
     
     private func handleDroppedFiles(_ urls: [URL]) {
         /*// Show window if not visible
         if let window = NSApplication.shared.windows.first {
             window.makeKeyAndOrderFront(nil)
             NSApp.activate(ignoringOtherApps: true)
         }
         
         // Get the ContentView's MosaicViewModel
         if viewModel == nil {
             if let window = NSApplication.shared.windows.first,
                let rootViewController = window.contentViewController,
                let hostingController = rootViewController as? NSHostingController<ContentView> {
                 viewModel = hostingController.rootView.viewModel
             }
         }
         
         // Process the dropped files
         let validFiles = urls.filter { url in
             let isVideo = UTType.movie.conforms(to: UTType(filenameExtension: url.pathExtension) ?? UTType.movie) ||
                          UTType.video.conforms(to: UTType(filenameExtension: url.pathExtension) ?? UTType.video)
             let isM3U8 = url.pathExtension.lowercased() == "m3u8"
             let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
             return isVideo || isM3U8 || isDirectory
         }
         
         // Update view model
         DispatchQueue.main.async { [weak self] in
             self?.viewModel?.inputPaths = validFiles.map { $0.path }
             
             if validFiles.count == 1 {
                 let url = validFiles[0]
                 if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false {
                     self?.viewModel?.inputType = .folder
                 } else if url.pathExtension.lowercased() == "m3u8" {
                     self?.viewModel?.inputType = .m3u8
                 } else {
                     self?.viewModel?.inputType = .files
                 }
             } else {
                 self?.viewModel?.inputType = .files
             }
             /*
             // Optionally start processing automatically
             if self?.viewModel?.autoProcessDroppedFiles ?? false {
                 self?.viewModel?.processInput()
             }*/
         }*/
     }
    /*
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(systemSymbolName: "mosaic", accessibilityDescription: "MosaicGen")
            statusButton.action = #selector(toggleWindow)
        }
        
        // Register services
        NSApp.servicesProvider = MosaicServiceHandler()
        
        // Set activation policy to regular app
        NSApp.setActivationPolicy(.regular)
    }
    */
    @objc func toggleWindow() {
        if let window = NSApplication.shared.windows.first {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // Handle app termination
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false if you want the app to stay running when all windows are closed
        false
    }
    
    // Handle dock icon click
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    // Optional: Handle Command-Q
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSApplication.shared.windows.forEach { $0.orderOut(nil) }
        return .terminateNow
    }
}

class DockTileView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw custom dock tile appearance if needed
        if let image = NSImage(systemSymbolName: "mosaic.fill", accessibilityDescription: nil) {
            image.draw(in: bounds)
        }
    }
}
