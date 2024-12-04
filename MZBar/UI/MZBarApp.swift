import SwiftUI
import UniformTypeIdentifiers

@main
struct MZBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
            .background(.ultraThinMaterial)
            .opacity(0.8)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered,
                        defer: false
                    )
                    window.contentView = NSHostingView(rootView: ContentView())
                    window.makeKeyAndOrderFront(nil)
                    window.center()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar icon and service
        setupMenuBarIcon()
        setupService()
    }
    
    private func setupMenuBarIcon() {
        // ... existing menu bar setup code ...
    }
    
    private func setupService() {
        NSApp.servicesProvider = MosaicServiceHandler()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Create a new window if none are visible
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: ContentView())
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
        return true
    }
}


