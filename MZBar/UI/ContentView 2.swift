//
//  ContentView 2.swift
//  MZBar
//
//  Created by Francois on 11/11/2024.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @StateObject public var viewModel = MosaicViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .mosaic
    
    enum TabSelection {
        case mosaic, preview, playlist, settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Mosaic Tab
            ScrollView {
                MainContentView(viewModel: viewModel, selectedTab: $selectedTab)
                    .padding()
            }
            .tabItem {
                Label("Mosaic", systemImage: "square.grid.3x3.fill")
            }
            .tag(TabSelection.mosaic)
            
            // Preview Tab
            ScrollView {
                MainContentView(viewModel: viewModel, selectedTab: $selectedTab)
                    .padding()
            }
            .tabItem {
                Label("Preview", systemImage: "play.square.fill")
            }
            .tag(TabSelection.preview)
            
            // Playlist Tab
            ScrollView {
                MainContentView(viewModel: viewModel, selectedTab: $selectedTab)
                    .padding()
            }
            .tabItem {
                Label("Playlist", systemImage: "music.note.list")
            }
            .tag(TabSelection.playlist)
            
            // Settings Tab
            ScrollView {
                MainContentView(viewModel: viewModel, selectedTab: $selectedTab)
                    .padding()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(TabSelection.settings)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(backgroundGradient)
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(.windowBackgroundColor).opacity(0.8),
                Color(.windowBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Main Content View
struct MainContentView: View {
    @ObservedObject var viewModel: MosaicViewModel
    @Binding var selectedTab: ContentView.TabSelection
    
    var body: some View {
        VStack(spacing: 24) {
            // Drop Zone
            /* if selectedTab != .settings {
             EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
             }*/
            
            // Tab-specific content
            switch selectedTab {
            case .mosaic:
                EnhancedMosaicSettings(viewModel: viewModel)
            case .preview:
                EnhancedPreviewSettings(viewModel: viewModel)
            case .playlist:
                EnhancedPlaylistSettings(viewModel: viewModel)
            case .settings:
                EnhancedSettingsView(viewModel: viewModel)
            }
            
            if selectedTab != .settings {
                // Action Buttons
                EnhancedActionButtons(viewModel: viewModel, mode: selectedTab)
                
                // Progress Section
                EnhancedProgressView(viewModel: viewModel)
            }
        }
        .padding(.bottom, 20) // Add bottom padding
    }
}

// MARK: - Enhanced Components
struct EnhancedDropZone: View {
    @ObservedObject var viewModel: MosaicViewModel
    @Binding var inputPaths: [(String, Int)]
    @Binding var inputType: MosaicViewModel.InputType
    @State private var isTargeted = false
    @State private var isHovered = false
    
    var body: some View {
        VStack {
            if viewModel.inputPaths.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
        .animation(.spring(), value: isHovered)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .border(.blue, width: isHovered ? 2 : 1)
                /*.overlay(
                 RoundedRectangle(cornerRadius: 16)
                 .strokeBorder(
                 LinearGradient(
                 colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                 startPoint: .topLeading,
                 endPoint: .bottomTrailing
                 ),
                 lineWidth: isHovered ? 2 : 1
                 )
                 )*/
                    .shadow(
                        color: .blue.opacity(0.1),
                        radius: isHovered ? 10 : 5,
                        x: 0,
                        y: isHovered ? 5 : 2
                    )
                
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Drop files here")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Videos, Folders, or M3U8 Playlists")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(40)
            }
            .frame(height: 160)
            .onHover { isHovered = $0 }
            .animation(.spring(), value: isTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
        }
    }
    
    private var fileListView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Files Ready")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { viewModel.inputPaths.removeAll() }) {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            
            VStack(spacing: 8) {
                ForEach(viewModel.inputPaths, id: \.0) { element in
                    FileRowView(path: element.0, count: element.1)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    struct pathCount{
        let path: String
        let count: Int
    }
    private func handleDrop(providers: [NSItemProvider]) async {
        var droppedPaths: [pathCount] = []
    
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        var gen = PlaylistGenerator()
                        let count: Int
                        do {
                            count = try await gen.findVideoFiles(in: url).count
                        } catch {
                            count = 0
                        }
                        droppedPaths.append(pathCount(path: url.path , count: count))
                    }
                } catch {
                    print("Error loading dropped item: \(error)")
                }
            }
        }
        DispatchQueue.main.async {
            withAnimation {
                self.inputPaths.append(contentsOf: droppedPaths.map { ($0.path, $0.count) })
                if droppedPaths.count == 1 {
                    let url = URL(fileURLWithPath: droppedPaths[0].path)
                    
                    if url.hasDirectoryPath {
                        self.inputType = .folder
                    } else if url.pathExtension.lowercased() == "m3u8" {
                        self.inputType = .m3u8
                    } else {
                        self.inputType = .files
                    }
                } else {
                    self.inputType = .files
                }
            }
        }
    }
    
    struct FileRowView: View {
        let path: String
        let count: Int
        
        var body: some View {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.blue)
                
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                Text("\(count) files")
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                
                
                
                
            }
            .padding(8)
            .background(Color(.quaternarySystemFill))
            .cornerRadius(8)
            
        }
        
        
    }
}
struct EnhancedMosaicSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Size Selection
            EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
            SettingsCard(title: "Size", icon: "ruler") {
                SegmentedPicker(
                    selection: $viewModel.selectedSize,
                    options: viewModel.sizes
                ) { size in
                    Text("\(size)px")
                }
            }
            
            // Density Selection
            SettingsCard(title: "Density", icon: "chart.bar.fill") {
                SegmentedPicker(
                    selection: $viewModel.selectedDensity,
                    options: viewModel.densities
                ) { density in
                    Text(density)
                }
            }
            
            // Format and Duration
            HStack(spacing: 24) {
                SettingsCard(title: "Format", icon: "doc.fill") {
                    FormatPicker(selection: $viewModel.selectedFormat)
                }
                
                SettingsCard(title: "Minimum Duration", icon: "clock.fill") {
                    DurationPicker(selection: $viewModel.selectedduration)
                }
            }
            HStack(spacing: 24) {
                
                OptionToggle("Overwrite", icon: "arrow.triangle.2.circlepath", isOn: $viewModel.overwrite)
                OptionToggle("Save at Root",icon: "folder", isOn: $viewModel.saveAtRoot)
                OptionToggle("create folders by movie size",  icon: "folder.badge.plus",isOn: $viewModel.seperate)
                OptionToggle("Add Full Path to mosaic name",   icon: "text.alignleft",isOn: $viewModel.addFullPath)
            }
            SettingsCard(title: "Concurrency", icon: "dial.high.fill")  {
                Picker("Concrrent Ops" , selection: $viewModel.concurrentOps)
                {
                    ForEach(viewModel.concurrent, id: \.self) { concurrent in
                        Text(String(concurrent)).tag(concurrent)
                    }
                }.pickerStyle(.segmented)
                    .onChange(of: viewModel.concurrentOps) {
                        viewModel.updateMaxConcurrentTasks()
                    }
            }
            
            /* Status Messages
            //if viewModel.isProcessing {
                StatusMessagesView(messages: [
                    .init(icon: "doc.text", text: viewModel.statusMessage1, type: .info),
                    .init(icon: "chart.bar.fill", text: viewModel.statusMessage2, type: .info),
                    .init(icon: "clock", text: viewModel.statusMessage3, type: .info),
                    .init(icon: "timer", text: viewModel.statusMessage4, type: .info)
                ].filter { !$0.text.isEmpty })
            //}*/
        }
    }
}

// MARK: - Preview Settings
struct EnhancedPreviewSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Duration Settings
            EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
            
            SettingsCard(title: "Preview Duration", icon: "clock.fill") {
                VStack(spacing: 12) {
                    // Slider
                    HStack {
                        Slider(
                            value: $viewModel.previewDuration,
                            in: 0...300,
                            step: 5
                        ) {
                            Text("Duration")
                        } minimumValueLabel: {
                            Text("0s")
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("300s")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Quick select buttons
                    HStack(spacing: 12) {
                        ForEach([30, 60, 120, 180], id: \.self) { duration in
                            Button("\(duration)s") {
                                withAnimation {
                                    viewModel.previewDuration = Double(duration)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.previewDuration == Double(duration) ? .blue : .secondary)
                        }
                    }
                }
            }
            
            // Quality Settings
            SettingsCard(title: "Density", icon: "dial.high.fill") {
                VStack(spacing: 12) {
                    // Density Picker
                    Picker("Density", selection: $viewModel.selectedDensity) {
                        ForEach(viewModel.densities, id: \.self) { density in
                            Text(density).tag(density)
                        }
                    }
                }
            }
            .pickerStyle(.segmented)
            SettingsCard(title: "Concurrency", icon: "dial.high.fill")  {
                Picker("Concrrent Ops" , selection: $viewModel.concurrentOps)
                {
                    ForEach(viewModel.concurrent, id: \.self) { concurrent in
                        Text(String(concurrent)).tag(concurrent)
                    }
                }.pickerStyle(.segmented)
                    .onChange(of: viewModel.concurrentOps) {
                        viewModel.updateMaxConcurrentTasks()
                    }
            }
            
            
            
        }
        .padding()
    }
    // Advanced Options
    /*SettingsCard(title: "Advanced Options", icon: "gearshape.2.fill") {
     VStack(alignment: .leading, spacing: 16) {
     Toggle("Hardware Acceleration", isOn: .constant(true))
     Toggle("High Quality Processing", isOn: .constant(true))
     Toggle("Generate Thumbnails", isOn: .constant(true))
     }
     }*/
}



struct ActionButton: View {
    let title: String
    let icon: String
    var isPrimary: Bool = false
    let action: () -> Void
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: isPrimary ? .infinity : nil)
                .padding(.horizontal, isPrimary ? nil : 20)
        }
        
    }
}
// MARK: - Playlist Settings
struct EnhancedPlaylistSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var selectedPlaylistType = 0
    
    var body: some View {
        VStack(spacing: 24) {
            // Playlist Type
            EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
            
            SettingsCard(title: "Playlist Type", icon: "music.note.list") {
                Picker("Type", selection: $selectedPlaylistType) {
                    Text("Standard").tag(0)
                    Text("Duration Based").tag(1)
                    Text("Custom").tag(2)
                }
                .pickerStyle(.segmented)
            }
            
            // Organization
            SettingsCard(title: "Organization", icon: "folder.fill") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Create Subfolders", isOn: .constant(true))
                    Toggle("Sort by Duration", isOn: .constant(true))
                    Toggle("Include Metadata", isOn: .constant(true))
                }
            }
            
            // Filters
            SettingsCard(title: "Filters", icon: "line.3.horizontal.decrease.circle.fill") {
                VStack(spacing: 16) {
                    DurationFilterView()
                    FileTypeFilterView()
                }
            }
            
            // Export Options
            SettingsCard(title: "Export", icon: "square.and.arrow.up.fill") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Generate M3U8", isOn: .constant(true))
                    Toggle("Include Previews", isOn: .constant(true))
                    Toggle("Create Backup", isOn: .constant(true))
                }
            }
        }
    }
}

// MARK: - Settings View
struct EnhancedSettingsView: View {
    @ObservedObject var viewModel: MosaicViewModel
    @AppStorage("hardwareAcceleration") private var hardwareAcceleration = true
    @AppStorage("autoProcessDrops") private var autoProcessDrops = false
    @AppStorage("theme") private var selectedTheme = 0
    
    var body: some View {
        VStack(spacing: 24) {
            // Performance Settings
            SettingsCard(title: "Performance", icon: "speedometer") {
                VStack(spacing: 16) {
                    HStack {
                        Text("Concurrent Operations")
                        Spacer()
                        Stepper(
                            value: .init(
                                get: { Double(viewModel.config.maxConcurrentOperations) },
                                set: { viewModel.config.maxConcurrentOperations = Int($0) }
                            ),
                            in: 1...32
                        ) {
                            Text("\(viewModel.config.maxConcurrentOperations)")
                                .monospacedDigit()
                        }
                    }
                    
                    Toggle("Hardware Acceleration", isOn: $hardwareAcceleration)
                    
                    Picker("Quality Preset", selection: .constant(0)) {
                        Text("Balanced").tag(0)
                        Text("Performance").tag(1)
                        Text("Quality").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            // Appearance
            SettingsCard(title: "Appearance", icon: "paintbrush.fill") {
                VStack(spacing: 16) {
                    Picker("Theme", selection: $selectedTheme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    ColorPicker("Accent Color", selection: .constant(.blue))
                }
            }
            
            // Behavior
            SettingsCard(title: "Behavior", icon: "gear") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Auto-process Dropped Files", isOn: $autoProcessDrops)
                    Toggle("Show Notifications", isOn: .constant(true))
                    Toggle("Remember Window Position", isOn: .constant(true))
                }
            }
            
            // Storage
            SettingsCard(title: "Storage", icon: "internaldrive.fill") {
                VStack(spacing: 16) {
                    StorageUsageView()
                    CacheManagementView()
                }
            }
        }
    }
}

// MARK: - Action Buttons
struct EnhancedActionButtons: View {
    @ObservedObject var viewModel: MosaicViewModel
    let mode: ContentView.TabSelection
    
    var body: some View {
        HStack(spacing: 16) {
            if viewModel.isProcessing {
                Button(role: .destructive) {
                    withAnimation {
                        viewModel.cancelGeneration()
                    }
                } label: {
                    Label("Cancel", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(style: .destructive))
                
            } else {
                Group {
                    switch mode {
                    case .mosaic:
                        primaryButton("Generate Mosaic", icon: "square.grid.3x3.fill") {
                            viewModel.processMosaics()
                        } .disabled(mode != .settings && viewModel.inputPaths.isEmpty)
                        
                        secondaryButton("Generate Today", icon: "calendar") {
                            viewModel.generateMosaictoday()
                        }
                        
                    case .preview:
                        primaryButton("Generate Previews", icon: "play.circle.fill") {
                            viewModel.processPreviews()
                        } .disabled(mode != .settings && viewModel.inputPaths.isEmpty)
                        
                    case .playlist:
                        primaryButton("Generate Playlist", icon: "music.note.list") {
                            if let path = viewModel.inputPaths.first?.0 {
                                viewModel.generatePlaylist(path)
                            }
                        } .disabled(mode != .settings && viewModel.inputPaths.isEmpty)
                        secondaryButton("Generate Playlist today", icon: "music.note.list") {
                            viewModel.generatePlaylisttoday()
                        }
                        
                    case .settings:
                        primaryButton("Save Settings", icon: "checkmark.circle.fill") {
                            viewModel.updateConfig()
                        } .disabled(mode != .settings && viewModel.inputPaths.isEmpty)
                    }
                }
                
            }
        }
    }
    
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ActionButtonStyle(style: .primary))
    }
    
    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(ActionButtonStyle(style: .secondary))
    }
}

// MARK: - Helper Views
struct ActionButtonStyle: ButtonStyle {
    enum Style {
        case primary, secondary, destructive
        
        var background: Material {
            switch self {
            case .primary: return .thick
            case .secondary, .destructive: return .regular
            }
        }
        
        var foreground: Color {
            switch self {
            case .primary: return .teal
            case .secondary: return .primary
            case .destructive: return .red
            }
        }
    }
    
    let style: Style
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(style.background)
            .foregroundStyle(style.foreground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct StorageUsageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Usage")
                .font(.headline)
            
            HStack {
                ProgressView(value: 0.7)
                    .tint(.blue)
                Text("70%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("14.2 GB of 20 GB used")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CacheManagementView: View {
    var body: some View {
        VStack(spacing: 8) {
            Button("Clear Cache") {
                // Clear cache action
            }
            .buttonStyle(.bordered)
            
            Text("Cache size: 1.2 GB")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DurationFilterView: View {
    @State private var minDuration: Double = 0
    @State private var maxDuration: Double = 3600
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration Range")
                .font(.subheadline)
            
            HStack {
                VStack {
                    Text("Min")
                        .font(.caption)
                    Text(formatDuration(minDuration))
                }
                
                Slider(value: $minDuration, in: 0...3600)
                
                VStack {
                    Text("Max")
                        .font(.caption)
                    Text(formatDuration(maxDuration))
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes)m"
    }
}

struct FileTypeFilterView: View {
    @State private var selectedTypes: Set<String> = ["mp4", "mov"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Types")
                .font(.subheadline)
            
            FlowLayout(spacing: 8) {
                ForEach(["mp4", "mov", "avi", "mkv", "m4v"], id: \.self) { type in
                    Toggle(type, isOn: .init(
                        get: { selectedTypes.contains(type) },
                        set: { isSelected in
                            if isSelected {
                                selectedTypes.insert(type)
                            } else {
                                selectedTypes.remove(type)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

// Helper view for flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentPosition = CGPoint.zero
            var lineHeight: CGFloat = 0
            var maxY: CGFloat = 0
            
            positions = []
            sizes = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentPosition.x + size.width > maxWidth && currentPosition.x > 0 {
                    currentPosition.x = 0
                    currentPosition.y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(currentPosition)
                sizes.append(size)
                
                lineHeight = max(lineHeight, size.height)
                maxY = max(maxY, currentPosition.y + size.height)
                currentPosition.x += size.width + spacing
            }
            
            size = CGSize(width: maxWidth, height: maxY)
        }
    }
}




struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            content
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}
struct SegmentedPicker<T: Hashable, Label: View>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> Label
    
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                label(option).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct OptionsGrid: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            OptionToggle("Overwrite", icon: "arrow.triangle.2.circlepath", isOn: $viewModel.overwrite)
            OptionToggle("Save at Root", icon: "folder", isOn: $viewModel.saveAtRoot)
            OptionToggle("Separate Folders", icon: "folder.badge.plus", isOn: $viewModel.seperate)
            OptionToggle("Full Path", icon: "text.alignleft", isOn: $viewModel.addFullPath)
        }
    }
}

struct OptionToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    init(_ title: String, icon: String, isOn: Binding<Bool>) {
        self.title = title
        self.icon = icon
        self._isOn = isOn
    }
    
    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon)
                .lineLimit(1)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
    }
}

struct EnhancedProgressView: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // Overall Progress
            ProgressCard(
                title: "Overall Progress",
                progress: viewModel.progressG,
                icon: "chart.bar.fill",
                color: .blue
            )
           // if viewModel.isProcessing {
                StatusMessagesView(messages: [
                    .init(icon: "doc.text", text: viewModel.statusMessage1, type: .info),
                    .init(icon: "chart.bar.fill", text: viewModel.statusMessage2, type: .info),
                    .init(icon: "clock", text: viewModel.statusMessage3, type: .info),
                    .init(icon: "timer", text: viewModel.statusMessage4, type: .info)
                ].filter { !$0.text.isEmpty })
            //}
            // Active Files
            if !viewModel.activeFiles.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Active Files", systemImage: "doc.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    ForEach(viewModel.activeFiles) { file in
                        FileProgressView(file: file) {
                            viewModel.cancelFile(file.id)
                        }
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Status Messages
   
        }
    }
}


struct ProgressCard: View {
    let title: String
    let progress: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                        .overlay(
                            Text("\(Int(progress * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                        )
                }
            }
            .frame(height: 20)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FileProgressView: View {
    let file: FileProgress
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(file.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Spacer()
                
                if !file.isComplete {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * file.progress)
                }
            }
            .frame(height: 12)
            
            Text(file.stage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FormatOptionsGrid: View {
    @State private var selectedFormat: PreviewFormat = .mp4
    @State private var quality: Double = 0.7
    
    enum PreviewFormat: String, CaseIterable {
        case mp4 = "MP4"
        case gif = "GIF"
        case webp = "WebP"
        case hevc = "HEVC"
        
        var icon: String {
            switch self {
            case .mp4: return "play.square.fill"
            case .gif: return "square.stack.fill"
            case .webp: return "photo.fill"
            case .hevc: return "play.square.stack.fill"
            }
        }
        
        var description: String {
            switch self {
            case .mp4: return "Best compatibility"
            case .gif: return "Web friendly"
            case .webp: return "Efficient size"
            case .hevc: return "High quality"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Format Selection
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(PreviewFormat.allCases, id: \.self) { format in
                    FormatButton(
                        format: format,
                        isSelected: format == selectedFormat,
                        action: { selectedFormat = format }
                    )
                }
            }
            
            // Quality Slider
            if selectedFormat != .gif {
                VStack(spacing: 8) {
                    HStack {
                        Text("Quality")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $quality) {
                        Text("Quality")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise.fill")
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "hare.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
            
            // Format Info
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text(selectedFormat.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

struct FormatButton: View {
    let format: FormatOptionsGrid.PreviewFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .blue)
                
                Text(format.rawValue)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? .blue : Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? .clear : .blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}

// MARK: - Format Picker
struct FormatPicker: View {
    @Binding var selection: String
    
    struct FormatOption: Identifiable {
        let id = UUID()
        let value: String
        let name: String
        let icon: String
        let description: String
    }
    
    private let formats: [FormatOption] = [
        .init(value: "heic", name: "HEIC", icon: "photo.fill",
              description: "High efficiency, smaller file size"),
        .init(value: "jpeg", name: "JPEG", icon: "photo.circle.fill",
              description: "Best compatibility"),
        .init(value: "png", name: "PNG", icon: "photo.stack.fill",
              description: "Lossless quality")
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Format Selection
            HStack(spacing: 2) {
                ForEach(formats) { format in
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            selection = format.value
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: format.icon)
                                .font(.headline)
                            Text(format.name)
                                .font(.caption2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selection == format.value ? .blue : Color.clear)
                        .foregroundStyle(selection == format.value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(4)
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Format Description
            if let selectedFormat = formats.first(where: { $0.value == selection }) {
                Text(selectedFormat.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Duration Picker
struct DurationPicker: View {
    @Binding var selection: Int
    
    struct DurationOption: Identifiable {
        let id = UUID()
        let seconds: Int
        let label: String
        
        static let options: [DurationOption] = [
            .init(seconds: 0, label: "No limit"),
            .init(seconds: 10, label: "10s"),
            .init(seconds: 30, label: "30s"),
            .init(seconds: 60, label: "1m"),
            .init(seconds: 300, label: "5m"),
            .init(seconds: 600, label: "10m")
        ]
    }
    
    var body: some View {
        Menu {
            ForEach(DurationOption.options) { option in
                Button {
                    selection = option.seconds
                } label: {
                    HStack {
                        Text(option.label)
                        if selection == option.seconds {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(DurationOption.options.first { $0.seconds == selection }?.label ?? "Select")
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Status Messages View
struct StatusMessagesView: View {
    let messages: [StatusMessage]
    @State private var previousMessages: [StatusMessage] = []
    
    struct StatusMessage: Identifiable, Equatable {
        let id = UUID()
        let icon: String
        let text: String
        let type: MessageType
        
        enum MessageType {
            case info, success, warning, error
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(messages) { message in
                HStack(spacing: 8) {
                    Image(systemName: message.icon)
                        .foregroundStyle(message.type.color)
                    
                    Text(message.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                
            }
        }
        //.animation(.spring(duration: 0.3), value: messages)
        .onChange(of: messages) { newMessages in
            previousMessages = messages
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    let title: String
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Window Controls
            // Title
            Text(title)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .center)
            
            // Right side spacer to balance window controls
            Rectangle()
                .fill(.clear)
                .frame(width: 48, height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background {
            if colorScheme == .dark {
                Color(.windowBackgroundColor).opacity(0.8)
            } else {
                Color(.windowBackgroundColor)
                    .opacity(0.9)
                    .overlay(.ultraThinMaterial)
            }
        }
        .onHover { isHovered = $0 }
    }
}


// Example usage and previews
#Preview("Format Picker") {
    FormatPicker(selection: .constant("heic"))
        .padding()
}

#Preview("Duration Picker") {
    DurationPicker(selection: .constant(30))
        .padding()
}

#Preview("Status Messages") {
    StatusMessagesView(messages: [
        .init(icon: "info.circle.fill", text: "Processing file: video.mp4", type: .info),
        .init(icon: "checkmark.circle.fill", text: "Successfully processed 3 files", type: .success),
        .init(icon: "exclamationmark.triangle.fill", text: "Skipped 1 file", type: .warning)
    ])
    .padding()
}

#Preview("Header") {
    HeaderView(title: "Mosaic Generator")
}


#Preview {
    FormatOptionsGrid()
        .padding()
}

#Preview {
    ContentView()
}

// Add more enhanced components...
