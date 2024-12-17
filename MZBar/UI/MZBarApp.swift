import SwiftUI
import UniformTypeIdentifiers

@main
struct MZBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
            .background(.ultraThinMaterial)
            .opacity(1)
            .ignoresSafeArea()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Window") {
                    // Create and retain a new window
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                        styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered,
                        defer: false
                    )

                    let contentView = ContentView()
                    window.styleMask.insert(.titled)
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden

                    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                    window.standardWindowButton(.closeButton)?.isHidden = false
                    window.standardWindowButton(.zoomButton)?.isHidden = false

                    window.contentView = NSHostingView(rootView: contentView)
                    window.makeKeyAndOrderFront(nil)
                    window.center()
                    
                    // Important: Set this to false to prevent premature deallocation
                    window.isReleasedWhenClosed = false
                    
                    // Store window in WindowManager to retain it
                    WindowManager.shared.addWindow(window)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// Add a WindowManager class to handle window retention
class WindowManager: NSObject {
    static let shared = WindowManager()
    private var windows: Set<NSWindow> = []
    
    func addWindow(_ window: NSWindow) {
        windows.insert(window)
        window.delegate = self
    }
    
    func removeWindow(_ window: NSWindow) {
        windows.remove(window)
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        removeWindow(window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupService()
    }
    
    private func setupService() {
        NSApp.servicesProvider = MosaicServiceHandler()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            let contentView = ContentView()
            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            window.center()
            window.isReleasedWhenClosed = false
            WindowManager.shared.addWindow(window)
        }
        return true
    }
}


