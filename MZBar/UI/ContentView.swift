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



extension UTType {
    static var m3u8Playlist: UTType {
        UTType(filenameExtension: "m3u8")!
    }
}

private struct ViewModelKey: EnvironmentKey {
    static let defaultValue: MosaicViewModel? = nil
}
extension EnvironmentValues {
    var mosaicViewModel: MosaicViewModel? {
        get { self[ViewModelKey.self] }
        set { self[ViewModelKey.self] = newValue }
    }
}
 enum TabSelection {
        case mosaic, preview, playlist, settings, navigator
    }
/// Main
struct ContentView: View {
    @StateObject public var viewModel = MosaicViewModel()
    
    
    var body: some View {
        ZStack {
            // Vibrant Background
            Color.gray
                .opacity(0.25)
                .ignoresSafeArea()
            
            Color.white
                .opacity(0.7)
                .blur(radius: 200)
                .ignoresSafeArea()
            
            GeometryReader { proxy in
                let size = proxy.size
                
                Circle()
                    .fill(viewModel.currentTheme.colors.primary)
                    .padding(50)
                    .blur(radius: 120)
                    .offset(x: -size.width/1.8, y: -size.height/5)
                
                Circle()
                    .fill(viewModel.currentTheme.colors.accent)
                    .padding(50)
                    .blur(radius: 150)
                    .offset(x: size.width/1.8, y: size.height/2)
            }
     
            NavigationSplitView {
                
                SidebarView(viewModel: viewModel)
                    .frame(alignment: .center)
                    .frame(width: 40)
                    //.opacity(0.2)
            }
            detail: {
                DetailView(viewModel: viewModel)
                    //.background(Color(.darkGray).opacity(0.8))
            }
            
            .onAppear {
                if viewModel.selectedMode == nil {
                    viewModel.selectedMode = .mosaic
                }
            }
        }
    }
  
}

private struct SidebarView: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        ZStack {
            ZStack {
                Color.gray
                .opacity(0.25)
                .ignoresSafeArea()
            
            Color.white
                .opacity(0.7)
                .blur(radius: 200)
                .ignoresSafeArea()
            
            GeometryReader { proxy in
                let size = proxy.size
                
                Circle()
                    .fill(viewModel.currentTheme.colors.primary)
                    .padding(50)
                    .blur(radius: 120)
                    .offset(x: -size.width/1.8, y: -size.height/5)
                
                Circle()
                    .fill(viewModel.currentTheme.colors.accent)
                    .padding(50)
                    .blur(radius: 150)
                    .offset(x: size.width/1.8, y: size.height/2)
            }

        VStack(spacing: 0) {
            List(selection: $viewModel.selectedMode) {
                        ForEach([
                            (TabSelection.mosaic, "square.grid.3x3.fill", "Mosaic"),
                            (TabSelection.preview, "play.square.fill", "Preview"),
                            (TabSelection.playlist, "music.note.list", "Playlist")
                        ], id: \.0) { tab, icon, title in
                            TabItemView(tab: tab, icon: icon, title: title, viewModel: viewModel)
                        }
                    }
                    .listStyle(.sidebar)
                
            Spacer()
            MosaicNavigatorButton(viewModel: viewModel)
        }
            Spacer()
            SettingsButton()
        }.frame(minWidth: 80, maxWidth: 80, alignment: .center)
            .padding(.horizontal, 16)
            .opacity(1)
    }
    }
}
#Preview("Sidepbar")
{
    let viewmodel = MosaicViewModel()

    SidebarView(viewModel: viewmodel)
}

private struct TabItemView: View {
    let tab: TabSelection
    let icon: String
    let title: String
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        NavigationLink(value: tab) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(viewModel.selectedMode == tab ? Color.white : Color.secondary)
                    .frame(width: 32, height: 32, alignment: .center)
                
            }
          //  .frame(maxWidth: .i)
            .padding(8)
            
        }
        .buttonStyle(.plain)
        .frame(alignment: .center)
        //.listRowBackground(viewModel.selectedMode == tab ? viewModel.currentTheme.colors.primary.opacity(0.1) : Color.clear)
       
        }
    }


private struct DetailView: View {
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some View {
        ZStack {
           /* LinearGradient(
            colors: [viewModel.currentTheme.colors.background, .black],
                           startPoint: .top,
                           endPoint: .bottom
            ).ignoresSafeArea().opacity(0.2)*/
           
            mainContent
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 10)
                        .opacity(0.01)
                )
                .opacity(1)
                .padding()
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.selectedMode {
        case .mosaic:
            VStack {
                EnhancedMosaicSettings(viewModel: viewModel)
                    .opacity(viewModel.isProcessing ? 0.05 : 1)
                
                if !viewModel.isProcessing && !viewModel.completedFiles.isEmpty {
                    Button(action: { viewModel.showMosaicBrowser() }) {
                        Label("Browse Mosaics", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
        case .preview:
            EnhancedPreviewSettings(viewModel: viewModel)
            .opacity(viewModel.isProcessing ? 0.05 : 1)
        case .playlist:
            EnhancedPlaylistSettings(viewModel: viewModel)
            .opacity(viewModel.isProcessing ? 0.05 : 1)
        case .settings:
            Text("Settings")
        default:
            EnhancedMosaicSettings(viewModel: viewModel)
            .opacity(viewModel.isProcessing ? 0.05 : 1)
        }
        if  viewModel.DisplayCloseButton{
                EnhancedProgressView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .padding()
                    .frame(minHeight: 500, maxHeight: 800, alignment: .top)
            }
    }
}

private struct SettingsButton: View {
    var body: some View {
        Button {
            // Handle settings
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "gear")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                Text("Settings")
                    .font(.caption)
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
private struct MosaicNavigatorButton: View {
    @ObservedObject var viewModel: MosaicViewModel
    var body: some View {
        Button(action: { viewModel.showMosaicNavigator() }) {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                Text("Mosaic Navigator")
                    .font(.caption)
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Tabs
struct EnhancedMosaicSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var isEditing2 = false
    
    private func calculateRectangleDimensions(
        gridWidth: CGFloat,
        gridSize: Int,
        spacing: CGFloat,
        aspectRatio: CGFloat,
        desiredGridHeight: CGFloat
    ) -> (width: CGFloat, height: CGFloat) {
        let totalSpacing = spacing * CGFloat(gridSize - 1)
        let availableWidth = gridWidth - totalSpacing
        
        if aspectRatio >= 1 {
            // Landscape or square
            let width = min((availableWidth / CGFloat(gridSize)), desiredGridHeight * aspectRatio)
            let height = width / aspectRatio
            return (width, height)
        } else {
            // Portrait
            let height = desiredGridHeight
            let width = height * aspectRatio
            return (width, height)
        }
    }
    
    // Add this helper function to EnhancedMosaicSettings:
private func getPresetColor(_ preset: String) -> Float {
    switch preset {
    case "Low": return 0.3
    case "Medium": return 0.6
    case "High": return 0.9
    default: return 0.6
    }
}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Drop Zone
                EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
                    .frame(maxWidth: .infinity)
                
                // Main Settings Card (Size, Density, Duration)
                SettingsCard(title: "Output Settings", icon: "slider.horizontal.3", viewModel: viewModel) {
                    VStack(spacing: 16) {
                        // Aspect Ratio Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aspect Ratio")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Picker("Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                                ForEach(MosaicViewModel.MosaicAspectRatio.allCases, id: \.self) { ratio in
                                    Text(ratio.rawValue).tag(ratio)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Size Section
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Output Size", systemImage: "ruler")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                            SegmentedPicker(selection: $viewModel.selectedSize, options: viewModel.sizes) { size in
                                Text("\(size)px")
                            }
                        }
                        
                        Divider()
                            .background(viewModel.currentTheme.colors.primary.opacity(0.2))
                   
                           
                           // Density Section
                           VStack(alignment: .leading, spacing: 12) {
                               Label("Density", systemImage: "chart.bar.fill")
                                   .foregroundStyle(viewModel.currentTheme.colors.primary)
                               
                               // Density Grid
                               GeometryReader { geometry in
                                   let cardWidth = geometry.size.width
                                   let gridWidth = cardWidth * 0.8
                                   let spacing: CGFloat = 2
                                   let gridSize = Int(sqrt(Double(Int(viewModel.selectedDensity * 10))))
                                   let desiredGridHeight: CGFloat = 80
                                   let rectangleHeight = (desiredGridHeight - (spacing * CGFloat(gridSize - 1))) / CGFloat(gridSize)
                                   let rectangleWidth = rectangleHeight * viewModel.selectedAspectRatio.ratio
                                   
                                   LazyVGrid(
                                       columns: Array(repeating: GridItem(.fixed(rectangleWidth), spacing: spacing), count: gridSize),
                                       spacing: spacing
                                   ) {
                                       ForEach(0..<(gridSize * gridSize), id: \.self) { _ in
                                           Rectangle()
                                               .fill(LinearGradient(
                                                   colors: [
                                                       viewModel.currentTheme.colors.primary,
                                                       viewModel.currentTheme.colors.accent
                                                   ],
                                                   startPoint: .leading,
                                                   endPoint: .trailing
                                               ))
                                               .opacity(0.1 + 0.1 * viewModel.selectedDensity)
                                               .frame(width: rectangleWidth, height: rectangleHeight)
                                               .cornerRadius(2)
                                       }
                                   }
                                   .frame(width: gridWidth)
                                   .frame(maxWidth: .infinity, alignment: .center)
                               }
                               .frame(height: 100)
                               
                               // Density Controls
                               HStack(spacing: 8) {
                                   ForEach(["XXS", "XS", "S", "M", "L", "XL", "XXL"], id: \.self) { label in
                                       Button {
                                           withAnimation {
                                               viewModel.selectedDensity = Double(densityValue(for: label))
                                           }
                                       } label: {
                                           Text(label)
                                               .font(.caption)
                                       }
                                       .buttonStyle(.bordered)
                                       .tint(viewModel.selectedDensity == Double(densityValue(for: label)) ?
                                             viewModel.currentTheme.colors.primary : .secondary)
                                   }
                               }.frame(maxWidth: .infinity, alignment: .center)
                           }
                           
                           Divider()
                           
   
    
                        Divider()
                            .background(viewModel.currentTheme.colors.primary.opacity(0.2))
                        
                        // Duration Section
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Duration Limit", systemImage: "clock.fill")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                            DurationPicker(selection: $viewModel.selectedduration)
                                .tint(viewModel.currentTheme.colors.primary)
                        }.frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        // Thumbnail Effects Section
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Thumbnail Effects", systemImage: "wand.and.stars")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                GridRow {
                                    OptionToggle("Add Border", icon: "square", isOn: $viewModel.addBorder)
                                    OptionToggle("Add Shadow", icon: "drop.fill", isOn: $viewModel.addShadow)
                                }
                            }
                            
                            // Border Controls (only show when border is enabled)
                            if viewModel.addBorder {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Border Color
                                    HStack {
                                        Text("Border Color")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        
                                        ColorPicker("", selection: $viewModel.borderColor)
                                            .labelsHidden()
                                    }
                                    
                                    // Border Width
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Border Width")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Int(viewModel.borderWidth))px")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Slider(
                                            value: $viewModel.borderWidth,
                                            in: 1...10,
                                            step: 1
                                        ) {
                                            Text("Border Width")
                                        } minimumValueLabel: {
                                            Text("1")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } maximumValueLabel: {
                                            Text("10")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .tint(viewModel.currentTheme.colors.primary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Output Settings Card (Format and Files)
                SettingsCard(title: "Output Settings", icon: "folder.fill", viewModel: viewModel) {
                    VStack(spacing: 24) {
                        // Format Section
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Format", systemImage: "doc.fill")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                            FormatPicker(selection: $viewModel.selectedFormat)
                        }
                        

                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
    Label("Output Quality", systemImage: "dial.high")
        .foregroundStyle(viewModel.currentTheme.colors.primary)
    
    HStack {
        Text("Quality: \(Int(viewModel.compressionQuality * 100))%")
            .foregroundStyle(.secondary)
        Spacer()
    }
    
    Slider(
        value: $viewModel.compressionQuality,
        in: 0.1...1.0,
        step: 0.1
    ) {
        Text("Quality")
    } minimumValueLabel: {
        Text("Low")
            .foregroundStyle(.secondary)
    } maximumValueLabel: {
        Text("High")
            .foregroundStyle(.secondary)
    }
    
    // Quality presets
    HStack(spacing: 8) {
        ForEach(["Low", "Medium", "High"], id: \.self) { preset in
            Button(action: {
                withAnimation {
                    switch preset {
                    case "Low":
                        viewModel.compressionQuality = 0.3
                    case "Medium":
                        viewModel.compressionQuality = 0.6
                    case "High":
                        viewModel.compressionQuality = 0.9
                    default:
                        break
                    }
                }
            }) {
                Text(preset)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(getPresetColor(preset) == viewModel.compressionQuality ? 
                  viewModel.currentTheme.colors.primary : .gray)
        }
    }.frame(maxWidth: .infinity, alignment: .center)
    .padding(.top, 4)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 8)

                        // Files Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("File Options", systemImage: "gear")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                            
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                GridRow {
                                    OptionToggle("Overwrite", icon: "arrow.triangle.2.circlepath", isOn: $viewModel.overwrite)
                                    OptionToggle("Save at Root", icon: "folder", isOn: $viewModel.saveAtRoot)
                                    OptionToggle("Create folders by size", icon: "folder.badge.plus", isOn: $viewModel.seperate)
                                    OptionToggle("Add Full Path", icon: "text.alignleft", isOn: $viewModel.addFullPath)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Concurrency Card

                
                // Action Buttons
                HStack(spacing: 16) {
                    Button {
                        viewModel.processMosaics()
                    } label: {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill")
                            Text("Generate Mosaic")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.currentTheme.colors.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputPaths.isEmpty)
                    
                    Button {
                        viewModel.generateMosaictoday()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text("Generate Today")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .foregroundColor(viewModel.currentTheme.colors.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(viewModel.currentTheme.colors.primary, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                
                // Progress View
                //EnhancedProgressView(viewModel: viewModel)
            }
            .padding(12)
        }
    }
    
    private func densityValue(for label: String) -> Int {
        switch label {
        case "XXS": return 1
        case "XS": return 2
        case "S": return 3
        case "M": return 4
        case "L": return 5
        case "XL": return 6
        case "XXL": return 7
        default: return 4
        }
    }
}
struct EnhancedPreviewSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var isEditing = false
    @State private var isEditing2 = false
    
    private func calculateRectangleDimensions(
        gridWidth: CGFloat,
        gridSize: Int,
        spacing: CGFloat,
        aspectRatio: CGFloat,
        desiredGridHeight: CGFloat
    ) -> (width: CGFloat, height: CGFloat) {
        let totalSpacing = spacing * CGFloat(gridSize - 1)
        let availableWidth = gridWidth - totalSpacing
        
        if aspectRatio >= 1 {
            // Landscape or square
            let width = min((availableWidth / CGFloat(gridSize)), desiredGridHeight * aspectRatio)
            let height = width / aspectRatio
            return (width, height)
        } else {
            // Portrait
            let height = desiredGridHeight
            let width = height * aspectRatio
            return (width, height)
        }
    }
    
    var body: some View {
        ScrollView{
            VStack(spacing: 20) {
                EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
                
                    SettingsCard(title: "Preview Setting", icon: "clock.fill", viewModel: viewModel) {
                         VStack(alignment: .center, spacing: 8) {
                            Label("Preview Duration", systemImage: "ruler")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
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
                            } onEditingChanged: { editing in
                                isEditing = editing
                            }
                            Text("\(Int(viewModel.previewDuration))s")
                            HStack(spacing: 8) {
                                ForEach([30, 60, 120, 180], id: \.self) { duration in
                                    Button("\(duration)s") {
                                        withAnimation {
                                            viewModel.previewDuration = Double(duration)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(viewModel.previewDuration == Double(duration) ? .blue : .secondary)
                                }.padding(.horizontal)
                            }
                        
                        Divider()
                        Label("Density", systemImage: "ruler")
                                .foregroundStyle(viewModel.currentTheme.colors.primary)
                        Spacer()
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let gridWidth = cardWidth * 0.8 // 80% of card width
                            let spacing: CGFloat = 2
                            let gridSize = Int(viewModel.previewDensity * 5)
                            
                            // Calculate rectangle dimensions based on aspect ratio
                            let (rectangleWidth, rectangleHeight) = calculateRectangleDimensions(
                                gridWidth: gridWidth,
                                gridSize: gridSize,
                                spacing: spacing,
                                aspectRatio: viewModel.selectedAspectRatio.ratio,
                                desiredGridHeight: 80
                            )
                            
                            // Center the grid
                            HStack(spacing: spacing) {
                                ForEach(0..<gridSize, id: \.self) { _ in
                                    Rectangle()
                                        .fill(LinearGradient(
                                            colors: [
                                                viewModel.currentTheme.colors.primary,
                                                viewModel.currentTheme.colors.accent
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .opacity(0.1 + 0.1 * viewModel.previewDensity)
                                        .frame(width: rectangleWidth, height: rectangleHeight)
                                        .cornerRadius(2)
                                }
                            }
                            .frame(width: gridWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(height: 100)
                        
                        // Density Controls
                        VStack(spacing: 8) {
                            Slider(
                                value: $viewModel.previewDensity,
                                in: 1...7,
                                step: 1
                            ) {
                                Text("Density")
                            } minimumValueLabel: {
                                Text("Low")
                                    .foregroundStyle(viewModel.currentTheme.colors.primary)
                            } maximumValueLabel: {
                                Text("High")
                                    .foregroundStyle(viewModel.currentTheme.colors.primary)
                            } onEditingChanged: { editing in
                                isEditing2 = editing
                            }
                            .tint(viewModel.currentTheme.colors.primary)
                            
                            // Density presets
                            HStack(spacing: 8) {
                                ForEach(["XXS", "XS", "S", "M", "L", "XL", "XXL"], id: \.self) { label in
                                    Button {
                                        withAnimation {
                                            viewModel.previewDensity = Double(densityValue(for: label))
                                        }
                                    } label: {
                                        Text(label)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(viewModel.previewDensity == Double(densityValue(for: label)) ? 
                                          viewModel.currentTheme.colors.primary : .secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                SettingsCard(title: "Quality", icon: "dial.high.fill", viewModel: viewModel)
                {
                    Picker("OutputFormat" , selection: $viewModel.codec)
                    {
                        ForEach(AVFoundation.AVAssetExportSession.allExportPresets(), id: \.self) { codec in
                            Text(String(codec)).tag(codec)
                        }
                    }.pickerStyle(.menu)
                        .onChange(of: viewModel.codec) {
                            viewModel.updateCodec()
                        }
                }
                
                

                
                
                EnhancedActionButtons(viewModel: viewModel, mode: viewModel.selectedMode)
               // EnhancedProgressView(viewModel: viewModel)
            }.padding(12)
        }
    }
    
    private func densityValue(for label: String) -> Int {
        switch label {
        case "XXS": return 1
        case "XS": return 2
        case "S": return 3
        case "M": return 4
        case "L": return 5
        case "XL": return 6
        case "XXL": return 7
        default: return 4
        }
    }
}
struct EnhancedPlaylistSettings: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var selectedPlaylistType = 0
    @State private var lastGeneratedPlaylistURL: URL? = nil
    @State private var isShowingFolderPicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Playlist Type
                EnhancedDropZone(viewModel: viewModel, inputPaths: $viewModel.inputPaths, inputType: $viewModel.inputType)
                SettingsCard(title: "Playlist Type", icon: "music.note.list", viewModel: viewModel) {
                    Picker("Type", selection: $viewModel.selectedPlaylistType) {
                        Text("Standard").tag(0)
                        Text("Duration Based").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 24) {
                    SettingsCard(title: "Calendar Options", icon: "music.note.list", viewModel: viewModel) {
                        DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                        
                        DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                    }
                }
                // Filters
                SettingsCard(title: "Filters", icon: "line.3.horizontal.decrease.circle.fill", viewModel: viewModel) {
                    VStack(spacing: 16) {
                        DurationFilterView()
                    }
                }
                
                // Add output folder selection
                SettingsCard(title: "Output Location", icon: "folder.fill", viewModel: viewModel) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(viewModel.playlistOutputFolder?.path ?? "Default Location")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button {
                                isShowingFolderPicker = true
                            } label: {
                                Text("Change")
                                    .foregroundColor(viewModel.currentTheme.colors.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.playlistOutputFolder != nil {
                            Button {
                                viewModel.resetPlaylistOutputFolder()
                            } label: {
                                Text("Reset to Default")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                EnhancedActionButtons(viewModel: viewModel, mode: viewModel.selectedMode)
              //  EnhancedProgressView(viewModel: viewModel)
                
                if let playlistURL = lastGeneratedPlaylistURL {
                    Button {
                        NSWorkspace.shared.selectFile(
                            playlistURL.path,
                            inFileViewerRootedAtPath: playlistURL.deletingLastPathComponent().path
                        )
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Show in Finder")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .foregroundColor(viewModel.currentTheme.colors.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(viewModel.currentTheme.colors.primary, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(12)
        }
        .onChange(of: viewModel.lastGeneratedPlaylistURL) { newURL in
            withAnimation {
                lastGeneratedPlaylistURL = newURL
            }
        }
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    viewModel.setPlaylistOutputFolder(selectedURL)
                }
            case .failure(let error):
                print("Folder selection failed: \(error.localizedDescription)")
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
        ScrollView{
            
            
            VStack(spacing: 24) {
                // Performance Settings
                SettingsCard(title: "Performance", icon: "speedometer", viewModel: viewModel) {
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
                        
                        Picker("Quality Preset", selection: .constant(0)) {
                            Text("Balanced").tag(0)
                            Text("Performance").tag(1)
                            Text("Quality").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                // Appearance
                SettingsCard(title: "Appearance", icon: "paintbrush.fill", viewModel: viewModel) {
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
                SettingsCard(title: "Behavior", icon: "gear", viewModel: viewModel) {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Auto-process Dropped Files", isOn: $autoProcessDrops)
                        Toggle("Show Notifications", isOn: .constant(true))
                        Toggle("Remember Window Position", isOn: .constant(true))
                    }
                }
                
                // Storage
                SettingsCard(title: "Storage", icon: "internaldrive.fill", viewModel: viewModel) {
                    VStack(spacing: 16) {
                        StorageUsageView()
                        CacheManagementView()
                    }
                }
            }
        }
    }
}
// MARK: - Enhanced Components
struct EnhancedDropZone: View {
    @ObservedObject var viewModel: MosaicViewModel
    @Binding var inputPaths: [(String, Int)]
    @Binding var inputType: MosaicViewModel.InputType
    @State private var isTargeted = false
    @State private var isHovered = false
      @State private var isLoading = false
    @State private var discoveredFiles = 0
    @State private var isShowingFilePicker = false

    var body: some View {
        ZStack {
            if inputPaths.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
        .frame(minHeight: 60)
        .background(viewModel.currentTheme.colors.surfaceBackground)
       
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? viewModel.currentTheme.colors.primary : Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
        )
        .animation(.spring(), value: isHovered)
            .onDrop(
                of: [.fileURL],
                isTargeted: $isTargeted
            ) { providers in
                Task {
                    await handleDrop(providers: providers)
                }
                return true
            }
            .onHover { hovering in
                withAnimation {
                    isHovered = hovering
                }
            }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 32))
            Text("Drop files here")
                .font(.headline)
                .foregroundStyle(viewModel.currentTheme.colors.primary)
            Text("Videos, Folders, or M3U8 Playlists")
                .font(.subheadline)
                .foregroundStyle(viewModel.currentTheme.colors.primary)
            
            Button(action: {
                selectFiles()
            }) {
                Label("Select Files", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.currentTheme.colors.primary)
            .padding(.top, 8)
            
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Counting files... (\(discoveredFiles) found)")
                        .foregroundColor(.secondary)
                    Button(action: {
                        isLoading = false
                        viewModel.cancelFileDiscovery()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity)
        .padding(32)
        .opacity(0.3)
    }
    
    private var fileListView: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(inputPaths.enumerated()), id: \.offset) { index, path in
                    FileRowView(path: path.0, count: path.1) {
                        removeFile(at: index)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 200)
    }
    
    private func removeFile(at index: Int) {
        withAnimation {
            inputPaths.remove(at: index)
            updateInputType()
        }
    }
    
    private func clearAll() {
        withAnimation {
            inputPaths.removeAll()
            inputType = .files
        }
    }
    
    private func updateInputType() {
        if inputPaths.isEmpty {
            inputType = .files
        } else if inputPaths.count == 1 {
            let url = URL(fileURLWithPath: inputPaths[0].0)
            if url.hasDirectoryPath {
                inputType = .folder
            } else if url.pathExtension.lowercased() == "m3u8" {
                inputType = .m3u8
            } else {
                inputType = .files
            }
        } else {
            inputType = .files
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) async -> Bool {
        isLoading = true
        discoveredFiles = 0
        viewModel.isFileDiscoveryCancelled = false
        
        var droppedPaths: [(path: String, count: Int)] = []
        
        for provider in providers {
            guard !viewModel.isFileDiscoveryCancelled else {
                break
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil)
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        let gen = PlaylistGenerator()
                        var count: Int = 0
                        do {
                            if url.pathExtension.lowercased() == "m3u8" {
                                let content = try String(contentsOf: url, encoding: .utf8)
                                count = content.components(separatedBy: .newlines)
                                    .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                                    .count
                                await MainActor.run {
                                    discoveredFiles = count
                                }
                            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false {
                                // Set up progress handler before finding files
                                gen.setDiscoveryProgress { count in
                                    Task { @MainActor in
                                        discoveredFiles = count
                                    }
                                }
                                do {
                                    let files = try await gen.findVideoFiles(in: url)
                                    if !viewModel.isFileDiscoveryCancelled {
                                        count = files.count
                                    }
                                } catch {
                                    count = 0
                                }
                            }
                            if !viewModel.isFileDiscoveryCancelled {
                                droppedPaths.append((path: url.path, count: count))
                            }
                            else {
                                droppedPaths.append((path: url.path, count: 0))
                            }
                        } catch {
                            count = 0
                        }
                    }
                } catch {
                    print("Error loading dropped item: \(error)")
                }
            }
        }
        
        DispatchQueue.main.async {
            withAnimation {
                //if !viewModel.isFileDiscoveryCancelled {
                    self.inputPaths.append(contentsOf: droppedPaths.map { ($0.path, $0.count) })
                    self.updateInputType()
                //}
                self.isLoading = false
            }
        }
        
        return true
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, UTType(filenameExtension: "m3u8")!]
        
        panel.begin { response in
            if response == .OK {
                Task {
                    isLoading = true
                    discoveredFiles = 0
                    viewModel.isFileDiscoveryCancelled = false
                    
                    var droppedPaths: [(path: String, count: Int)] = []
                    
                    for url in panel.urls {
                        guard !viewModel.isFileDiscoveryCancelled else {
                            break
                        }
                        
                        let gen = PlaylistGenerator()
                        var count: Int = 0
                        
                        do {
                            if url.pathExtension.lowercased() == "m3u8" {
                                let content = try String(contentsOf: url, encoding: .utf8)
                                count = content.components(separatedBy: .newlines)
                                    .filter { !$0.hasPrefix("#") && !$0.isEmpty }
                                    .count
                                await MainActor.run {
                                    discoveredFiles = count
                                }
                            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false {
                                gen.setDiscoveryProgress { count in
                                    Task { @MainActor in
                                        discoveredFiles = count
                                    }
                                }
                                let files = try await gen.findVideoFiles(in: url)
                                if !viewModel.isFileDiscoveryCancelled {
                                    count = files.count
                                }
                            }
                            
                            if !viewModel.isFileDiscoveryCancelled {
                                droppedPaths.append((path: url.path, count: count))
                            }
                        } catch {
                            print("Error processing selected file: \(error)")
                        }
                    }
                    
                    await MainActor.run {
                        withAnimation {
                            self.inputPaths.append(contentsOf: droppedPaths)
                            self.updateInputType()
                            self.isLoading = false
                        }
                    }
                }
            }
        }
    }
}

struct FileRowView: View {
    let path: String
    let count: Int
    var onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 12))
            
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 12))
            
            Spacer()
            
            Text("\(count) files")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color(.quaternarySystemFill))
        .cornerRadius(6)
    }
}





private func calculateParameters(movieDuration: Double, previewDuration: Double, density: Double) -> (Int, Double) {
    // Calculate extract count and duration
    let initialRate = 12.0
    let decayFactor = 0.2
    let durationInMinutes = movieDuration
    let baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / density
    
    let extractCount = Int(ceil(movieDuration * baseExtractsPerMinute))
    var extractDuration = previewDuration / Double(extractCount)
    
    let minExtractDuration = 5.0 // Minimum duration of each extract
    if extractDuration < minExtractDuration {
        extractDuration = minExtractDuration
    }
    
    return (extractCount, extractDuration)
}



struct ExtractionParametersView: View {
    @State private var videoDuration: Double = 120.0 // In minutes
    @State private var density: Double = 1.0
    private let minExtractDuration: Double = 5.0 // Example value
    
    var body: some View {
        VStack {
            Text("Extraction Parameters Visualizer")
                .font(.headline)
            
            // Video Duration Slider
            HStack {
                Text("Video Duration: \(Int(videoDuration))m")
                Slider(value: $videoDuration, in: 0...240, step: 1)
            }
            .padding()
            
            // Density Slider
            HStack {
                Text("Density: \(String(format: "%.1f", density))x")
                Slider(value: $density, in: 0.5...2.0, step: 0.1)
            }
            .padding()
            var width: CGFloat = 0.0
            var height: CGFloat = 0.0
            // Curve Graph
            GeometryReader { geometry in
                Path { path in
                    width = geometry.size.width
                    height = geometry.size.height
                    
                    // Draw the decaying curve
                    for minute in stride(from: 0.0, to: videoDuration, by: 1.0) {
                        let decayFactor = 0.2
                        let initialRate = 12.0
                        let durationInMinutes = minute / 60.0
                        let baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / density
                        
                        let x = width * (minute / videoDuration)
                        let y = height * (1 - CGFloat(baseExtractsPerMinute / 12.0))
                        
                        if minute == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
                
                // Minimum extract duration line
                Path { path in
                    let y = height * (1 - CGFloat(minExtractDuration / 60.0))
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(Color.red, lineWidth: 1)
            }
            .frame(height: 200)
            .padding()
            
            // Preview Duration Bar
            HStack {
                Text("Total Preview Duration")
                Rectangle()
                    .fill(Color.green)
                    .frame(width: CGFloat(videoDuration * density), height: 20)
            }
            .padding()
        }
        .padding()
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
        
    }
}

// MARK: - Playlist Settings


// MARK: - Action Buttons
struct EnhancedActionButtons: View {
    @ObservedObject var viewModel: MosaicViewModel
    let mode: TabSelection
    
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
                        secondaryButton("Generate Date Range Playlist", icon: "calendar.badge.clock") {
                            viewModel.generateDateRangePlaylist()
                        }
                        
                    case .settings:
                        primaryButton("Save Settings", icon: "checkmark.circle.fill") {
                            viewModel.updateConfig()
                        } .disabled(mode != .settings && viewModel.inputPaths.isEmpty)
                    
                    case .navigator:
                        primaryButton("Generate Mosaic", icon: "square.grid.3x3.fill") {
                            viewModel.processMosaics()
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
    @State private var selectedTab = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Progress
                SettingsCard(title: "Concurrency", icon: "dial.high.fill", viewModel: viewModel) {
                    Picker("Concurrent Ops", selection: $viewModel.concurrentOps) {
                        ForEach(viewModel.concurrent, id: \.self) { concurrent in
                            Text(String(concurrent)).tag(concurrent)
                        }
                    }.pickerStyle(.segmented)
                        .onChange(of: viewModel.concurrentOps) {
                            viewModel.updateMaxConcurrentTasks()
                        }
                }
                
                // Show Cancel button during processing, Close button when complete
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
                    Button {
                        withAnimation {
                            viewModel.isProcessing = false
                            viewModel.DisplayCloseButton = false
                        }
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(style: .secondary))
                }
                
                DynamicGridProgress(
                    title: "Overall Progress",
                    progress: viewModel.progressG,
                    icon: "chart.bar.fill",
                    color: viewModel.currentTheme.colors.primary,
                    fileCount: viewModel.inputPaths.count
                ).transition(.scale.combined(with: .opacity))
                
                // Only show Browse Mosaics button when processing is complete
                if !viewModel.isProcessing && !viewModel.completedFiles.isEmpty {
                    Button(action: { viewModel.showMosaicBrowser() }) {
                        Label("Browse Mosaics", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                
                StatusMessagesView(
                    messages: [
                        .init(icon: "doc.text", text: viewModel.statusMessage1, type: .info),
                        .init(icon: "chart.bar.fill", text: viewModel.statusMessage2, type: .info),
                        .init(icon: "clock", text: viewModel.statusMessage3, type: .info),
                        .init(icon: "timer", text: viewModel.statusMessage4, type: .info),
                    ]
                )
                
                ProcessingQueueView(viewModel: viewModel)
            }
        }
    }
}


struct CompletedFilesView: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Completed Files")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !viewModel.completedFiles.isEmpty {
                    Text("\(viewModel.completedFiles.count) files")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            
            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.completedFiles) { file in
                            FileCompletedView(
                                file: file,
                                onCancel: {},
                                onRetry: {}
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(minHeight: 200, maxHeight: 200)
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemFill))
        .cornerRadius(8)
    }
}

struct QueueProgressView: View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var isExpanded = false
    @State private var lastFileId: UUID?
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with toggle button
            HStack {
                Text("Queue Status")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !viewModel.queuedFiles.isEmpty {
                    Text("\(viewModel.queuedFiles.count) files")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            if isExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(viewModel.queuedFiles, id: \.self) { file in
                                FileProgressView(
                                    file: file,
                                    onCancel: { viewModel.cancelFile(file.id) },
                                    onRetry: { viewModel.retryPreview(for: file.id) }
                                )
                                .id(file.id) // Use file.id as the scroll identifier
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(minHeight: 200, maxHeight: 200)
                    .onChange(of: viewModel.queuedFiles) { newFiles in
                        // Find the first processing file
                        if let processingFile = newFiles.first(where: { !$0.isComplete && !$0.isCancelled }) {
                            withAnimation {
                                proxy.scrollTo(processingFile.id, anchor: .center)
                            }
                            lastFileId = processingFile.id
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemFill))
        .cornerRadius(8)
    }
}

struct DynamicGridProgress: View {
    let title: String
    let progress: Double
    let icon: String
    let color: Color
    let fileCount: Int
    
    private var columns: Int {
        min(max(Int(ceil(sqrt(Double(fileCount)))), 8), 100)
    }
    private var rows: Int {
        min(max(Int(ceil(Double(fileCount) / Double(columns))), 4), 5)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            GridProgressView(progress: progress, color: color, columns: columns, rows: rows)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct GridProgressView: View {
    let progress: Double
    let color: Color
    let columns: Int
    let rows: Int
    
    private var percentageOverlay: some View {
        Text("\(Int(progress * 100))%")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.trailing, 8)
    }
    
    private func gridContent(size: CGSize) -> some View {
        let itemSize = min(
            (size.width * 0.8 - CGFloat(columns - 1) * 4) / CGFloat(columns),
            (size.height * 0.8 - CGFloat(rows - 1) * 4) / CGFloat(rows))
        return GridContent(itemSize: itemSize, progress: progress, color: color, columns: columns, rows: rows)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var body: some View {
        GeometryReader { geometry in
            gridContent(size: geometry.size)
        }
        .frame(height: 120)
        .overlay(alignment: .trailing) {
            percentageOverlay
        }
    }
}

private struct GridContent: View {
    let itemSize: CGFloat
    let progress: Double
    let color: Color
    let columns: Int
    let rows: Int
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(itemSize), spacing: 4), count: columns), spacing: 4) {
            ForEach(0..<(columns * rows), id: \.self) { index in
                GridCell(index: index, totalCells: columns * rows, progress: progress, color: color, itemSize: itemSize)
            }
        }
    }
}

private struct GridCell: View {
    let index: Int
    let totalCells: Int
    let progress: Double
    let color: Color
    let itemSize: CGFloat
    
    var body: some View {
        let cellProgress = Double(index + 1) / Double(totalCells)
        let isActive = cellProgress <= progress
        
        RoundedRectangle(cornerRadius: 4)
            .fill(isActive ? 
                  LinearGradient(colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing) :
                  LinearGradient(colors: [color.opacity(0.2), color.opacity(0.2)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(width: itemSize, height: itemSize)
            .scaleEffect(isActive ? 1 : 0.65)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.3), value: isActive)
            .opacity(isActive ? progress : 0.5)
    }
}

struct FileProgressView: View {
    let file: FileProgress
    let onCancel: () -> Void
    let onRetry: () -> Void
    @State private var showPreview = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            
            Text(file.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 11))
            
            Spacer()
            
            if file.isCancelled {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if file.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                
                if file.stage.contains("Exporting") {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            SwiftUICore.GeometryReader { geometry in
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

struct FileCompletedView: View {
    let file: FileProgress
    let onCancel: () -> Void
    let onRetry: () -> Void
    @State private var showPreview = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            
            Text(file.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 11))
            
            Spacer()
            
            if file.isCancelled {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if file.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            Text(file.stage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if file.isComplete, let outputURL = file.outputURL
            {
                // Add preview button when complete and output URL exists
                Button(action: { showPreview = true }) {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                }
                
                .buttonStyle(.plain)
                .popover(isPresented: $showPreview) {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        PreviewPopupView(url: outputURL, isPresented: $showPreview)
                    } else {
                        Text("Preview not available")
                            .padding()
                    }
                }
                Button(action: {
                    if file.isComplete,  let folderURL = file.outputURL?.deletingLastPathComponent() {
                        NSWorkspace.shared.open(folderURL)
                    }
                }) {
                    Label("Show in Finder", systemImage: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
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
    
    let durations = [
        (0, "No limit"),
        (10, "10s"),
        (30, "30s"),
        (60, "1m"),
        (300, "5m"),
        (600, "10m")
    ]
    
    var body: some View {
        Picker("Duration", selection: $selection) {
            ForEach(durations, id: \.0) { duration, label in
                Text(label)
                    .tag(duration)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
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
struct PreviewPopupView: View {
    let url: URL
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding()
            }
            
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 800, maxHeight: 600)
            } else {
                Text("Unable to load preview")
                    .foregroundStyle(.secondary)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .frame(maxWidth: .infinity, maxHeight: 2000)
    }
}


// Example usage and previews
#Preview("SidebarView") {
    let view = MosaicViewModel.init()
    ContentView(viewModel: view)
}





#Preview("Preview") {
    let view = MosaicViewModel.init()
   // view.selectedMode = TabSelection.mosaic
    EnhancedPreviewSettings(viewModel: view)
}


/*
#Preview("Msaic") {
    let view = MosaicViewModel.shared
    EnhancedMosaicSettings(viewModel: view)
}
#Preview("Playlis")
{
    let view = MosaicViewModel.shared
    EnhancedPlaylistSettings(viewModel: view)
}

#Preview("Sidebar")
{
    let view = MosaicViewModel.shared
    SidebarView(viewModel: view)
}

#Preview("ContentView")
{
    let view = MosaicViewModel.shared
    ContentView(viewModel: view)
}
*/

// MARK: - Mosaic Browser
struct MosaicBrowserView: View {
    @ObservedObject var viewModel: MosaicViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFileId: ResultFiles.ID?
    
    // Add onDisappear to handle cleanup
    var body: some View {
        NavigationSplitView {
            List(viewModel.doneFiles, id: \.id, selection: $selectedFileId) { file in
                VStack(alignment: .leading) {
                    Text(file.video.lastPathComponent)
                        .font(.headline)
                    Text(file.video.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Source Files")
        } detail: {
            MosaicDetailView(file: selectedFile)
        }
        .onDisappear {
            // Ensure cleanup when view disappears
            selectedFileId = nil
        }
    }
    
    var selectedFile: ResultFiles? {
        viewModel.doneFiles.first { $0.id == selectedFileId }
    }
}

struct MosaicDetailView: View {
    let file: ResultFiles?
    @State private var isShowingIINA = false
    
    var body: some View {
        VStack {
            if let file = file {
                if let image = NSImage(contentsOf: file.output) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Button(action: {
                        openInIINA(sourceFile: file.video.path())
                    }) {
                        Label("Play in IINA", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            } else {
                Text("Select a file to view its mosaic")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mosaic Preview")
    }
    
    private func openInIINA(sourceFile: String) {
        let url = URL(fileURLWithPath: sourceFile)
        let iinaURL = URL(string: "iina://open?url=\(url.path)")!
        NSWorkspace.shared.open(iinaURL)
    }
}

