import SwiftUI
import UniformTypeIdentifiers

@main
struct MosaicGenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(systemSymbolName: "mosaic", accessibilityDescription: "MosaicGen")
            statusButton.action = #selector(togglePopover)
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: ContentView())
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MosaicViewModel()
    var body: some View {
        VStack(spacing: 5) {
            DropZoneView(inputPath: $viewModel.inputPath)
                .frame(height: 100)
                .frame(width: 200)
                .padding()
            
            if !viewModel.inputPath.isEmpty {
                Text("Selected folder: \(viewModel.inputPath)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ProgressView(value: viewModel.progressG)
                .frame(width: 150 )
                .progressViewStyle(.circular)
            Text("\(Int(viewModel.progressG * 100))%")
            Text(viewModel.statusMessage)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(width:500)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Picker("W", selection: $viewModel.selectedSize) {
                    ForEach(viewModel.sizes, id: \.self) { size in
                        Text("\(size) px").tag(size)
                    }
                }
                .frame(width: 120)
                
                Picker("D", selection: $viewModel.selectedDensity) {
                    ForEach(viewModel.densities, id: \.self) { density in
                        Text("\(density)").tag(density)
                    }
                }
                .frame(width: 120)
                Picker("F", selection: $viewModel.selectedFormat) {
                    ForEach(viewModel.formats, id: \.self) { format in
                        Text("\(format)").tag(format)
                    }
                }
                .frame(width: 120)
            }.pickerStyle(.automatic)
            HStack{
                Toggle("Overwrite", isOn: $viewModel.overwrite)
                Toggle("SaveAtRoot", isOn: $viewModel.saveAtRoot)
                Toggle("SeparateFolders", isOn: $viewModel.seperate)
            }
            if viewModel.isProcessing {
                Button("Cancel") {
                    viewModel.cancelGeneration()
                }
                .foregroundColor(.red)
                .padding()
            } else {
                Button("Generate Mosaic") {
                    viewModel.generateMosaic()
                }.padding()
                    .disabled(viewModel.inputPath.isEmpty)
            }
            
            
        }.frame(width: 600)
    }
}
struct DropZoneView: View {
    @Binding var inputPath: String
    @State private var isTargeted = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isTargeted ? Color.blue : Color.gray, lineWidth: 2)
                )
            
            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.largeTitle)
                Text("Drop folder here")
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                await handleDrop(providers: providers)
            }
            return true
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) async {
        var Myurl: URL = URL(fileURLWithPath: "")
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Myurl = url
                    }
                } catch {
                    print("Error loading dropped item: \(error)")
                }
                
            }
            DispatchQueue.main.async {
                self.inputPath = Myurl.path
            }
        }
    }
    
}
    class MosaicViewModel: ObservableObject {
        @Published var inputPath: String = ""
        @Published var progressG: Double = 0
        @Published var progressT: Double = 0
        @Published var progressM: Double = 0
        @Published var statusMessage: String = ""
        @Published var selectedSize = 5120
        @Published var selectedDensity = "M"
        @Published var selectedFormat = "heic"
        @Published var isProcessing: Bool = false
        @Published var overwrite: Bool = false
        @Published var saveAtRoot: Bool = false
        @Published var seperate: Bool = false

        private var generator: MosaicGenerator?
        let sizes = [2000, 5120, 10000]
        let densities = ["XXS", "XS", "S", "M", "L", "XL", "XXL"]
        let formats = ["heic", "jpeg"]
        func generateMosaic() {
            guard !inputPath.isEmpty else {
                statusMessage = "Please select a folder first."
                return
            }
            func formatDuration(_ duration: Double) -> String {
                let duration = Int(duration)
                let seconds = Double(duration % 60)
                let minutes = Double((duration / 60) % 60)
                let hours = Double(duration / 3600)
                return "\(hours.format(0, minimumIntegerPartLength: 2)):\(minutes.format(0, minimumIntegerPartLength: 2)):\(seconds.format(0, minimumIntegerPartLength: 2))"
            }
            isProcessing = true
            statusMessage = "Starting mosaic generation..."
            generator = MosaicGenerator(debug: false, renderingMode: .auto, maxConcurrentOperations: 20, saveAtRoot: saveAtRoot,separate: seperate)
            let startTime = CFAbsoluteTimeGetCurrent()
            var TotalCount:Double = 0.0
            var text:String = ""
            generator?.setProgressHandlerG { [weak self] progress in
                DispatchQueue.main.async {
                    TotalCount = self?.generator?.getProgressSize() ?? 0.0

                    self?.progressG = progress
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    var itemsPerSecond = 0.0
                    var estimatedTimeRemaining = 0.0
                    if progress > 0 {
                        itemsPerSecond = Double(progress) / duration
                        estimatedTimeRemaining = Double((TotalCount - progress) / itemsPerSecond)
                    }
                    let estimatedTimeRemainingString = formatDuration(estimatedTimeRemaining)
                    text = "Processing \(TotalCount) Files \(Int(progress*100))% complete \nETA :\(estimatedTimeRemainingString)\n\(String(format: "%.2f", itemsPerSecond*100)) items/sec"
                    self?.statusMessage = text
                   
                }
            }
            
            Task {
                do {
                    try await generator?.processFiles(
                        input: inputPath,
                        width: selectedSize,
                        density: selectedDensity,
                        format: selectedFormat,
                        overwrite: overwrite,
                        preview: false
                    )
                    DispatchQueue.main.async {
                        self.statusMessage = "Mosaic generation completed successfully!"
                        self.progressG = 0.0
                        let notification = NSUserNotification()
                        notification.title = "Mosaic Generation Complete"
                        NSUserNotificationCenter.default.deliver(notification)
                        self.isProcessing = false
                    }
                }catch is CancellationError {
                    DispatchQueue.main.async {
                        self.statusMessage = "Mosaic generation was cancelled."
                        self.isProcessing = false
                    }
                }
                catch {
                    DispatchQueue.main.async {
                        self.statusMessage = "Error generating mosaic: \(error.localizedDescription)"
                        self.isProcessing = false
                    }
                }
            }
        }
        func cancelGeneration() {
                generator?.cancelProcessing()
                statusMessage = "Cancelling mosaic generation..."
            }
    }

#Preview {
    ContentView()
}
