//
//  ContentView.swift
//  MZBar
//
//  Created by Francois on 01/11/2024.
//
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation


struct ContentView: View {
    @StateObject private var viewModel = MosaicViewModel()
    @State private var isEditing = false
    @Environment(\.colorScheme) var colorScheme
    @State private var showActiveFiles = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .background(.ultraThinMaterial)
            
            // Mode Selection
            ModeSelectionView(selectedMode: $viewModel.selectedMode)
                .padding(.vertical, 8)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Input Zone (common to all modes)
                    if viewModel.selectedMode != .settings
                    {
                        inputSection
                    }
                    // Settings Panel (changes based on mode)
                    ZStack {
                        // Mosaic Settings
                        if viewModel.selectedMode == .mosaic {
                            mosaicSettingsSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            
                        }
                        
                        // Preview Settings
                        if viewModel.selectedMode == .preview {
                            previewSettingsSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                        
                        // Playlist Settings
                        if viewModel.selectedMode == .playlist {
                            playlistSettingsSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                        }
                        if viewModel.selectedMode == .settings {
                            globalSettingsSection
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                
                        }
                        
                    }
                    .animation(.interpolatingSpring, value: viewModel.selectedMode)
                    
                    
                    
                        // Action Section (updates based on mode)
                        actionSection
                        if viewModel.selectedMode != .settings
                        {
                        // Progress Section (common to all modes)
                        progressSection
                    }
                }
                .padding()
            }
        }
        .frame(width: 800, height: 1000)
        .background(Color(.windowBackgroundColor))
    }
    /// Header
    private var header: some View {
        HStack {
            Label {
                Text("Mosaic Generator")
                    .font(.title3.weight(.medium))
            } icon: {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.blue)
            }
            Spacer()
        }
        .padding()
        
    }
    
    
    /// Previews
    ///
    // Preview Settings Panel
    private var previewSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Preview Settings", icon: "play.circle.fill")
            
            
            VStack(spacing: 16) {
                settingRow("Preview Duration", icon: "clock.fill") {
                    // We'll need to add this to the ViewModel
                    Slider(value: $viewModel.previewDuration,
                           in: 0...300,
                           step: 5
                    ){Text("duration")
                    }minimumValueLabel: {
                        Text("0 s")
                    }maximumValueLabel: {
                        Text("300 s")
                    }onEditingChanged: { editing in
                        isEditing = editing
                    }
                    Text("(\(String(format: "%.2f", viewModel.previewDuration)) s)")
                    
                    Picker("", selection: $viewModel.selectedDensity) {
                        ForEach(viewModel.densities, id: \.self) { density in
                            Text(density).tag(density)
                        }
                    }

                }
                settingRow("Mac conurent Duration", icon: "clock.fill") {
                    Picker("" , selection: $viewModel.concurrentOps)
                    {
                        ForEach(viewModel.concurrent, id: \.self) { concurrent in
                            Text(String(concurrent)).tag(concurrent)
                        }
                    }.pickerStyle(.segmented)
                    ActionButton(
                        title: "update",
                        icon: "play.circle.fill",
                        isPrimary: true,
                        action: {
                            viewModel.updateMaxConcurrentTasks()
                        }, viewModel: viewModel// Will need to update this to handle previews
                        )
                    
                    
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.quaternarySystemFill)))
        }
    }
    private var globalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Preview Settings", icon: "play.circle.fill")
            
                Form {
                         
                               Stepper("Max Concurrent Operations: \(viewModel.config.maxConcurrentOperations)", value: $viewModel.config.maxConcurrentOperations, in: 1...10)

                               Picker("Video Export Preset", selection: $viewModel.config.videoExportPreset) {
                                   ForEach(availableExportPresets, id: \.self) { preset in
                                       Text(preset).tag(preset)
                                   }
                               }

                               Slider(value: $viewModel.config.compressionQuality, in: 0...1, step: 0.1) {
                                   Text("Compression Quality: \(String(format: "%.1f", viewModel.config.compressionQuality))")
                               }

                               Toggle("Use Accurate Timestamps", isOn: $viewModel.config.accurateTimestamps)
                           }
                       
                   

                var availableExportPresets: [String] {
                       [
                           AVAssetExportPresetHighestQuality,
                           AVAssetExportPresetMediumQuality,
                           AVAssetExportPreset640x480,
                           AVAssetExportPreset960x540,
                           AVAssetExportPreset1280x720,
                           AVAssetExportPreset1920x1080,
                           AVAssetExportPresetHEVC1920x1080
                       ]
                   }
                }
            
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.quaternarySystemFill)))
        }
    
    
    // Playlist Settings Panel (placeholder for now)
    private var playlistSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Playlist Settings", icon: "list.bullet")
            
            Text("Playlist settings coming soon...")
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.quaternarySystemFill)))
        } .modifier(ThemedSectionBackground(theme: viewModel.currentTheme.colors))
    }
    
    
    /// Sections
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Input Files", icon: "square.and.arrow.down.fill")
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.quaternarySystemFill))
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                
                DropZoneView(inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType, viewModel: viewModel)
                    .frame(height: 120)
            }
        }
    }
    
    private var mosaicSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Processing Settings", icon: "slider.horizontal.3")
                .foregroundStyle(viewModel.currentTheme.colors.primary)
            VStack(spacing: 16) {
                // Size Picker
                settingRow("Size", icon: "ruler") {
                    Picker("", selection: $viewModel.selectedSize) {
                        ForEach(viewModel.sizes, id: \.self) { size in
                            Text("\(size)px").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Density Picker
                settingRow("Density", icon: "chart.bar.fill") {
                    Picker("", selection: $viewModel.selectedDensity) {
                        ForEach(viewModel.densities, id: \.self) { density in
                            Text(density).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                }
                
                // Format & Duration
                HStack(spacing: 20) {
                    settingRow("Format", icon: "doc.fill") {
                        FormatPicker(selection: $viewModel.selectedFormat)
                    }
                    
                    settingRow("Ignore videos shorter than (s)", icon: "clock.fill") {
                        DurationPicker(selection: $viewModel.selectedduration)
                    }
                }
                
                settingRow("File Handling", icon: "folder.fill") {
                    HStack( spacing: 10) {
                        OptionToggle(isOn: $viewModel.overwrite,
                                     icon: "arrow.triangle.2.circlepath",
                                     label: "Overwrite")
                        OptionToggle(isOn: $viewModel.saveAtRoot,
                                     icon: "folder",
                                     label: "Save at Root")
                        OptionToggle(isOn: $viewModel.seperate,
                                     icon: "folder.badge.plus",
                                     label: "create folders by movie size")
                        OptionToggle(isOn: $viewModel.addFullPath,
                                     icon: "text.alignleft",
                                     label: "Add Full Path to mosaic name")
                    }
                }
                
                settingRow("Processing", icon: "doc.badge.gearshape.fill") {
                    
                    HStack(spacing: 10) {
                        /*OptionToggle(isOn: $viewModel.customLayout,
                         icon: "square.grid.3x3.fill",
                         label: "Custom Layout")*/
                        LayoutPicker(selection: $viewModel.layoutName)
                        
                    }
                }
                settingRow("Mac conurent Duration", icon: "clock.fill") {
                    Picker("" , selection: $viewModel.concurrentOps)
                    {
                        ForEach(viewModel.concurrent, id: \.self) { concurrent in
                            Text(String(concurrent)).tag(concurrent)
                        }
                    }.pickerStyle(.segmented)
                    ActionButton(
                        title: "update",
                        icon: "play.circle.fill",
                        isPrimary: true,
                        action: {
                            viewModel.updateMaxConcurrentTasks()
                        }, viewModel: viewModel// Will need to update this to handle previews
                        )
                    
                    
                }
                
            }
            .modifier(ThemedSectionBackground(theme: viewModel.currentTheme.colors))
            .padding()
            
        }
    }
    
    private var actionSection: some View {
        HStack(spacing: 12) {
            if viewModel.isProcessing {
                Button(action: { viewModel.cancelGeneration() }) {
                    Label("Cancel", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                switch viewModel.selectedMode {
                case .mosaic:
                    ActionButton(
                        title: "Generate Mosaic",
                        icon: "square.grid.3x3.fill",
                        isPrimary: true,
                        action: {
                            viewModel.processInput() }, viewModel: viewModel
                    )
                    .disabled(viewModel.inputPaths.isEmpty)
                    
                    ActionButton(
                        title: "Generate Today",
                        icon: "calendar",
                        action: {
                            viewModel.generateMosaictoday() }, viewModel: viewModel
                    )
                    
                case .preview:
                    ActionButton(
                        title: "Generate Previews",
                        icon: "play.circle.fill",
                        isPrimary: true,
                        action: {
                            viewModel.processInput()
                        }, viewModel: viewModel// Will need to update this to handle previews
                    )
                    .disabled(viewModel.inputPaths.isEmpty)
                    
                case .playlist:
                    ActionButton(
                        title: "Generate Playlist",
                        icon: "list.bullet",
                        isPrimary: true,
                        action: { viewModel.generatePlaylist(viewModel.inputPaths[0]) }, viewModel: viewModel
                    )
                    .disabled(viewModel.inputPaths.isEmpty)
                    
                case .settings:
                    ActionButton(
                        title: "Save Setting",
                        icon: "list.wheel",
                        isPrimary: true,
                        action: { viewModel.updateConfig()}, viewModel: viewModel
                    )
                }
            }
            
        }.animation(.spring( ), value: viewModel.selectedMode)
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Progress", icon: "chart.bar.fill")
            
            VStack(alignment: .leading, spacing: 12) {
                // Global Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: viewModel.progressG)
                        .progressViewStyle(.linear)
                        .frame(height: 8)
                        .overlay(
                            Text("\(Int(viewModel.progressG * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                }
                
                // Individual File Progress Bars
                if !viewModel.activeFiles.isEmpty {
                    DisclosureGroup(
                        isExpanded: $showActiveFiles,
                        content: {
                            ForEach(viewModel.activeFiles, id: \.id) { file in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.filename)
                                            .font(.caption)
                                            .lineLimit(1)
                                        ProgressView(value: file.progress)
                                            .progressViewStyle(.linear)
                                            .frame(height: 6)
                                    }
                                    
                                    Button(action: {
                                        viewModel.cancelFile(file.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .opacity(file.isComplete ? 0 : 1)
                                    }
                                    .disabled(file.isComplete)
                                    .frame(width: 24, height: 24)
                                    .padding(.leading, 8)
                                }
                                .padding(.vertical, 2)
                            }
                        },
                        label: {
                            HStack {
                                Text("Active Files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(viewModel.activeFiles.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(.quaternarySystemFill))
                                    .cornerRadius(8)
                            }
                            .padding(.vertical, 4)
                        }
                    )
                    .padding(.top, 8)
                }
                
                // Status Messages
                VStack(alignment: .leading, spacing: 8) {
                    StatusMessage(icon: "doc.text", message: viewModel.statusMessage1)
                    StatusMessage(icon: "chart.bar.fill", message: viewModel.isProcessing ? viewModel.statusMessage2 : "")
                    StatusMessage(icon: "clock", message: viewModel.isProcessing ? viewModel.statusMessage3 : "")
                    StatusMessage(icon: "timer", message: viewModel.isProcessing ? viewModel.statusMessage4 : "")
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.quaternarySystemFill)))
        }
    }
    
    
    private func settingRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            
        }
    }
    
    struct ModeSelectionView: View {
        @Binding var selectedMode: ProcessingMode
        
        var body: some View {
            HStack(spacing: 0) {
                ForEach([ProcessingMode.mosaic, .preview, .playlist, .settings], id: \.self) { mode in
                    modeButton(for: mode)
                }
            }
            .padding(.horizontal)
        }
        
        private func modeButton(for mode: ProcessingMode) -> some View {
            Button(action: { withAnimation(.spring()) { selectedMode = mode } }) {
                HStack {
                    Image(systemName: iconName(for: mode))
                    Text(title(for: mode))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedMode == mode ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(selectedMode == mode ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
        
        
        
        private func iconName(for mode: ProcessingMode) -> String {
            switch mode {
            case .mosaic: return "square.grid.3x3"
            case .preview: return "play.circle"
            case .playlist: return "list.bullet"
            case .settings: return "gearshape.circle"
            }
            
        }
        
        private func title(for mode: ProcessingMode) -> String {
            switch mode {
            case .mosaic: return "Mosaic"
            case .preview: return "Preview"
            case .playlist: return "Playlist"
            case .settings: return "Settings"
            }
        }
    }
    
    // Helper Views
    struct SectionHeader: View {
        let title: String
        let icon: String
        
        var body: some View {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            
            
        }
    }
    
    struct OptionGroup<Content: View>: View {
        let title: String
        let icon: String
        let content: Content
        
        init(title: String, icon: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.icon = icon
            self.content = content()
        }
        
        var body: some View {
            VStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                content
            }
        }
    }
    
    struct OptionToggle: View {
        @Binding var isOn: Bool
        let icon: String
        let label: String
        
        var body: some View {
            Toggle(isOn: $isOn) {
                Label(label, systemImage: icon)
                    .labelStyle(.titleAndIcon)
            }
            .toggleStyle(.checkbox)
            
        }
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
            .buttonStyle(ThemedButtonStyle(
                isPrimary: isPrimary,
                theme: viewModel.currentTheme.colors
            ))
            .tint(isPrimary ? .accentColor : .primary)
        }
    }
    // Theme-aware button style
    struct ThemedButtonStyle: ButtonStyle {
        let isPrimary: Bool
        let theme: AppTheme.ThemeColors
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPrimary ? theme.primary : theme.surfaceBackground)
                )
                .foregroundStyle(isPrimary ? .white : theme.primary)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }
    // Theme-aware section background modifier
    struct ThemedSectionBackground: ViewModifier {
        let theme: AppTheme.ThemeColors
        
        func body(content: Content) -> some View {
            content
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.surfaceBackground)
                )
        }
    }
    struct StatusMessage: View {
        let icon: String
        let message: String
        
        var body: some View {
            Label {
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    struct FormatPicker: View {
        @Binding var selection: String
        
        var body: some View {
            Picker("", selection: $selection) {
                Text("HEIC").tag("heic")
                Text("JPEG").tag("jpeg")
            }
            .pickerStyle(.segmented)
            .padding(0.0)
            .frame(width: 120)
        }
    }
    struct LayoutPicker: View {
        @Binding var selection: String
        
        var body: some View {
            Picker("", selection: $selection) {
                Text("Classic").tag("Classic")
                Text("Focus").tag("Focus")
            }
            .pickerStyle(.segmented)
            .padding(0.0)
            .frame(width: 120)
        }
    }
    
    
    
    
    struct DurationPicker: View {
        @Binding var selection: Int
        
        var body: some View {
            Picker("", selection: $selection) {
                Text("0s").tag(0)
                Text("10s").tag(10)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
                Text("300s").tag(300)
                Text("600s").tag(600)
            }
            .pickerStyle(.menu)
            .frame(minWidth: 60, alignment: .leading)
        }
    }
    
    
    struct TooglePicker: View {
        @Binding var selection: Bool
        
        var body: some View {
            Toggle("", isOn: $selection)
        }
    }
    
    struct DropZoneView: View {
        @Binding var inputPaths: [String]
        @Binding var inputType: MosaicViewModel.InputType
        @State private var isTargeted = false
        @ObservedObject var viewModel: MosaicViewModel
        
        var body: some View {
            VStack(spacing: 12) {
                // Drop Zone
                if inputPaths.isEmpty {
                    emptyStateView
                } else {
                    fileListView
                }
            }
        }
        
        private var emptyStateView: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ?
                          viewModel.currentTheme.colors.primary.opacity(0.1) :
                            viewModel.currentTheme.colors.surfaceBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isTargeted ?
                                viewModel.currentTheme.colors.primary :
                                    Color.gray.opacity(0.2),
                                lineWidth: 2
                            )
                    )
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.largeTitle)
                        .foregroundStyle(viewModel.currentTheme.colors.primary)
                    Text("Drop folder, M3U8, or files here")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)
            .animation(.spring(), value: isTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
        }
        
        private var fileListView: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dropped Items")
                        .font(.headline)
                        .foregroundStyle(viewModel.currentTheme.colors.primary)
                    
                    Spacer()
                    
                    Button(action: { inputPaths.removeAll() }) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundStyle(viewModel.currentTheme.colors.primary)
                    }
                    .buttonStyle(.borderless)
                }
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(inputPaths, id: \.self) { path in
                            FileRowView(
                                path: path,
                                
                                onDelete: { removeItem(path) },
                                count: 0,
                                viewModel: viewModel
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
                
                HStack {
                    Label("\(inputPaths.count) items", systemImage: "number")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Add More") {
                        // This will allow the view to accept more drops
                        isTargeted = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(viewModel.currentTheme.colors.primary)
                }
                .font(.caption)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.currentTheme.colors.surfaceBackground)
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
        }
        
        private func removeItem(_ path: String) {
            withAnimation {
                inputPaths.removeAll { $0 == path }
                if inputPaths.isEmpty {
                    isTargeted = false
                }
            }
        }
        private func handleDrop(providers: [NSItemProvider]) async {
            var droppedPaths: [String] = []
            
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            droppedPaths.append(url.path)
                        }
                    } catch {
                        print("Error loading dropped item: \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                withAnimation {
                    self.inputPaths.append(contentsOf: droppedPaths)
                    
                    if droppedPaths.count == 1 {
                        let url = URL(fileURLWithPath: droppedPaths[0])
                        
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
    }
    struct FileRowView: View {
        let path: String
        let onDelete: () -> Void
        let count: Int
        @ObservedObject var viewModel: MosaicViewModel
        
        var body: some View {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(viewModel.currentTheme.colors.accent)
                
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                Text(String(count))
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(viewModel.currentTheme.colors.surfaceBackground.opacity(0.5))
            .cornerRadius(6)
        }
    }
    
    
 
}

#Preview {
    ContentView()
}

