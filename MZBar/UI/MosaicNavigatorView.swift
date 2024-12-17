import SwiftUI
import SQLite
import QuickLook

struct MosaicEntry: Identifiable, Equatable, Hashable {
    let id: Int64
    let movieFilePath: String
    let mosaicFilePath: String
    let size: String
    let density: String
    let folderHierarchy: String
    let hash: String
    let duration: Double
    let resolutionWidth: Double
    let resolutionHeight: Double
    let codec: String
    let videoType: String
    let creationDate: String
    
    static func == (lhs: MosaicEntry, rhs: MosaicEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    var resolution: String {
        return "\(Int(resolutionWidth))x\(Int(resolutionHeight))"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


struct MosaicNavigatorView: SwiftUI.View {
    @ObservedObject var viewModel: MosaicViewModel
    @State private var searchQuery: String = ""
    @State private var filterFolder: String = ""
    @State private var filterResolution: String = ""
    @State private var filterType: String = ""
    @State private var filterWidth: String = ""
    @State private var filterDensity: String = ""
    @State private var selectedFileId: MosaicEntry.ID?
    @State private var showFilters: Bool = false
    @State private var viewMode: ViewMode = .list
    @State private var isHovered = false    
    
    enum ViewMode {
        case list, folder
    }
    

    var body: some SwiftUI.View {
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
            
            VStack {
                // Top toolbar
                HStack {
                   /* if viewModel.allMosaics.isEmpty {
                        Button(action: {
                            Task {
                                await viewModel.fetchMosaics()
                            }
                        }) {
                            Label("Load Database", systemImage: "arrow.down.circle")
                        }
                        .disabled(viewModel.isLoading)
                    } else {*/
                        Button(action: {
                            Task {
                                await viewModel.refreshMosaics()
                            }
                        }) {
                            Label("Refresh Database", systemImage: "arrow.clockwise")
                        
                        .disabled(viewModel.isLoading)
                    }
                    
                    Spacer()
                    
                    Button("Clean Database") {
                        DatabaseManager.shared.cleanDatabase()
                        Task {
                            await viewModel.refreshMosaics()
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding([.top, .leading, .trailing])
                
                if viewModel.isLoading {
                    ProgressView("Loading mosaics...")
                        .padding()
                } else if viewModel.allMosaics.isEmpty {
                    Text("Click 'Load Database' to start")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                } else {
                    VStack (spacing: 8){
                        // Search and Filter Controls
                        Picker("View Mode", selection: $viewMode) {
                            Image(systemName: "list.bullet").tag(ViewMode.list)
                            Image(systemName: "folder").tag(ViewMode.folder)
                        }
                        .padding(.leading)
                        .pickerStyle(.segmented)
                        
                        TextField("Search by file name", text: $searchQuery)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        
                        HStack {
                            FilterMenu(title: "Folder", selection: $filterFolder, options: viewModel.availableFolders)
                            FilterMenu(title: "Resolution", selection: $filterResolution, options: viewModel.availableResolutions)
                        }
                        HStack {
                            FilterMenu(title: "Type", selection: $filterType, options: ["XS", "S", "M", "L", "XL"])
                            FilterMenu(title: "Width", selection: $filterWidth, options: viewModel.availableWidths)
                            FilterMenu(title: "Density", selection: $filterDensity, options: viewModel.availableDensities)
                        }        .background(viewModel.currentTheme.colors.surfaceBackground)
       
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? viewModel.currentTheme.colors.primary : Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
        )
        
                        
                        .padding(.horizontal)
                        
                        NavigationSplitView {
                            VStack() {
                                // Content view
                                if viewMode == .list {
                                    ListModeView(
                                        mosaics: filteredMosaics,
                                        selectedFileId: $selectedFileId,
                                        viewModel: viewModel
                                    )
                                    
                                    .onChange(of: viewModel.allMosaics) { _ in
                                        print("📊 MosaicNavigatorView: allMosaics updated, count: \(viewModel.allMosaics.count)")
                                        
                                    }
                                    
                                } else {
                                    FolderModeView(
                                        mosaics: filteredMosaics,
                                        selectedFileId: $selectedFileId
                                    )
                                }
                            }.navigationSplitViewColumnWidth(
                                min: 150, ideal: 300, max: 400)
                            .cornerRadius(12)
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(isHovered ? viewModel.currentTheme.colors.primary : Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
    )
                        }

        
                        detail: {
                            MosaicNavigatorDetailView(file: selectedMosaic, viewModel: viewModel)
                        }
                    }.containerBackground(.clear, for: .window)
                        .containerBackground(.clear, for: .window)
                                .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? viewModel.currentTheme.colors.primary : Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
        )

                        
                }
                
                
                var filteredMosaics: [MosaicEntry] {
                    print("🔍 Filtering mosaics, total count: \(viewModel.allMosaics.count)")
                    return viewModel.allMosaics.filter { mosaic in
                        (searchQuery.isEmpty || mosaic.movieFilePath.localizedCaseInsensitiveContains(searchQuery)) &&
                        (filterFolder.isEmpty || mosaic.folderHierarchy.contains(filterFolder)) &&
                        (filterResolution.isEmpty || mosaic.resolution == filterResolution) &&
                        (filterType.isEmpty || mosaic.videoType == filterType) &&
                        (filterWidth.isEmpty || String(Int(mosaic.resolutionWidth)) == filterWidth) &&
                        (filterDensity.isEmpty || mosaic.density == filterDensity)
                    }
                }
                
                var selectedMosaic: MosaicEntry? {
                    filteredMosaics.first { $0.id == selectedFileId }
                }
            }
        }.onAppear{
            task {
                await viewModel.fetchMosaics()
            }
        }
    }
}

struct ListModeView: SwiftUI.View {
    let mosaics: [MosaicEntry]
    @SwiftUI.Binding var selectedFileId: MosaicEntry.ID?
    @ObservedObject var viewModel: MosaicViewModel
    @State private var sortOption: SortOption = .mostRecent
    @State private var sortAscending: Bool = false
    @State private var displayLimit: Int = 20000
    @State private var isLoadingMore = false
    @FocusState private var isFocused: Bool
    
    enum SortOption: String, CaseIterable {
        case mostRecent = "Most Recent"
        case resolution = "Resolution"
        case duration = "Duration"
        case codec = "Codec"
    }
    
    struct MovieGroup: Identifiable {
        let id: String
        let versions: [MosaicEntry]
        let primaryVersion: MosaicEntry
        
        init(id: String, versions: [MosaicEntry]) {
            self.id = id
            self.versions = versions
            self.primaryVersion = versions.max(by: { $0.id < $1.id }) ?? versions[0]
        }
    }
    
    @State private var cachedGroups: [MovieGroup] = []
    @State var keyMonitor: Any?
    
    var body: some SwiftUI.View {
        VStack {
            // Sort controls
            HStack {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Button(action: { sortAscending.toggle() }) {
                    Image(systemName: sortAscending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(sortAscending ? .blue : .blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            Text("\(mosaics.count) items (\(displayLimit) shown)")
                .foregroundStyle(.secondary)
        }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(visibleGroups) { group in
                        MovieRow(group: group, isSelected: selectedFileId == group.primaryVersion.id, viewModel: viewModel)
                            .id(group.primaryVersion.id)
                            .onTapGesture {
                                selectedFileId = group.primaryVersion.id
                            }
                            .padding(10)
                            //.background(selectedFileId == group.primaryVersion.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                
                        .focusable()
                      //  .focused($isFocused)
                        .focusEffectDisabled(true)

                        .onChange(of: selectedFileId) { newId in
                            if let id = newId {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                        .onKeyPress(.upArrow, action: moveSelectionUp)
                        .onKeyPress(.downArrow, action: moveSelectionDown)
                        //.onKeyPress(.leftArrow, action: moveSelectionDown)
                        //.onKeyPress(.rightArrow, action: moveSelectionUp)
                    
                    if displayLimit < cachedGroups.count {
                        ProgressView()
                            .padding()
                            .onAppear {
                                loadMore()
                            }
                    }
                }
                
            }

        }
        .navigationTitle("Mosaic List")
        .onChange(of: mosaics) { _ in updateCache() }
        .onChange(of: sortOption) { _ in updateCache() }
        .onChange(of: sortAscending) { _ in updateCache() }
        .onAppear { updateCache() }
        .background(.opacity(0.1))
        .cornerRadius(6)
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: Notification.Name("SelectMosaicEntry"),
                object: nil,
                queue: .main
            ) { notification in
                if let mosaicId = notification.userInfo?["mosaicId"] as? Int64 {
                    selectedFileId = mosaicId
                }
            }
        }
    }
    

    
    private var visibleGroups: [MovieGroup] {
        Array(cachedGroups.prefix(displayLimit))
    }
    
    private func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            displayLimit += 50
            isLoadingMore = false
        }
    }
    
    private func updateCache() {
        let start = CFAbsoluteTimeGetCurrent()
        print("📊 Updating group cache with \(mosaics.count) mosaics...")
        
        // Group by movie file path
        let grouped = Dictionary(grouping: mosaics) { $0.movieFilePath }
        var groups = grouped.map { MovieGroup(id: $0.key, versions: $0.value) }
        
        // Sort groups
        groups.sort { group1, group2 in
            let first = group1.primaryVersion
            let second = group2.primaryVersion
            
            let result = switch sortOption {
            case .mostRecent:
                first.id > second.id
            case .resolution:
                (first.resolutionWidth * first.resolutionHeight) > (second.resolutionWidth * second.resolutionHeight)
            case .duration:
                first.duration > second.duration
            case .codec:
                first.codec < second.codec
            }
            return sortAscending ? !result : result
        }
        
        cachedGroups = groups
        
        let duration = CFAbsoluteTimeGetCurrent() - start
        print("🕒 Cache update took \(String(format: "%.3f", duration))s")
        print("📊 Cached \(groups.count) groups")
    }
    
    private func moveSelectionUp() -> KeyPress.Result {
        guard let currentId = selectedFileId,
             
              let currentIndex = cachedGroups.firstIndex(where: { $0.primaryVersion.id == currentId }),
             
              currentIndex > 0 else {
            return .ignored
        }
        print("🔄 Moving selection up to index: \(currentIndex - 1)")
        
        selectedFileId = cachedGroups[currentIndex - 1].primaryVersion.id
        return .handled
    }
    
    private func moveSelectionDown() -> KeyPress.Result {
        guard  let currentId = selectedFileId,
              let currentIndex = cachedGroups.firstIndex(where: { $0.primaryVersion.id == currentId }),
              currentIndex < cachedGroups.count - 1 else {
            return .ignored
        }
        
        selectedFileId = cachedGroups[currentIndex + 1].primaryVersion.id
        return .handled
    }

    private func fileRow(mosaic: MosaicEntry) -> some SwiftUI.View {
        Button(action: { selectedFileId = mosaic.id }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mosaic.movieFilePath.lastPathComponent)
                HStack {
                    Text(mosaic.resolution)
                    Text("•")
                    Text(mosaic.videoType)
                    Text("•")
                    Text(mosaic.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .cornerRadius(8)
        .contextMenu {
            Button("Generate New Variant") {
                // Call function to generate new variant
                generateNewVariant(for: mosaic)
            }
        }
    }

    private func generateNewVariant(for mosaic: MosaicEntry) {
        // Implement the logic to generate a new variant
        // This will involve calling the processMosaics function with the selected settings
    }
}


struct MovieRow: SwiftUI.View {
    let group: ListModeView.MovieGroup
    let isSelected: Bool
    @ObservedObject var viewModel: MosaicViewModel
    @State private var showingVariantSettings = false
    
    var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row with version count
            HStack(spacing: 8) {
                Text(group.primaryVersion.movieFilePath.lastPathComponent)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                
                if group.versions.count > 1 {
                    Text("\(group.versions.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }
            
            // Folder path
            Text(group.primaryVersion.folderHierarchy)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Metadata row
            HStack(spacing: 12) {
                Label(group.primaryVersion.resolution, systemImage: "rectangle.split.3x3")
                Label(group.primaryVersion.formattedDuration, systemImage: "clock")
                Label(group.primaryVersion.codec, systemImage: "film")
                Label(group.primaryVersion.videoType, systemImage: "video")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            
            // Version chips
            if group.versions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(group.versions.sorted(by: { $0.id > $1.id }), id: \.id) { version in
                            Text("\(version.size)px")
                                .font(.system(.caption2, design: .rounded))
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                showingVariantSettings = true
            }) {
                Label("Generate New Variant", systemImage: "plus.square.on.square")
            }
        }
        .sheet(isPresented: $showingVariantSettings) {
            MosaicVariantSettingsView(
                viewModel: viewModel,
                moviePath: group.primaryVersion.movieFilePath
            )
        }
    }
}


struct FolderModeView: SwiftUI.View {
    let mosaics: [MosaicEntry]
    @SwiftUI.Binding var selectedFileId: MosaicEntry.ID?
    @State private var currentPath: String = ""
    @State private var thumbnailSize: CGFloat = 150
    @FocusState private var isFocused: Bool
    
    var body: some SwiftUI.View {
        let groupedMosaics = groupMosaicsByFolder(mosaics)
        
        HSplitView {
            // Folder List
            List {
                if !currentPath.isEmpty {
                    Button(action: navigateUp) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("..")
                        }
                    }
                }
                
                ForEach(groupedMosaics.keys.sorted(), id: \.self) { key in
                    if let items = groupedMosaics[key] {
                        if items.first?.isFolder == true {
                            folderRow(name: key, count: items.count)
                        }
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 300)
            .listStyle(SidebarListStyle())
            
            // Grid View
            ScrollViewReader { proxy in
                VStack {
                    // Thumbnail size slider
                    HStack {
                        Image(systemName: "photo")
                        Slider(value: $thumbnailSize, in: 100...300)
                        Image(systemName: "photo.fill")
                    }
                    .padding()
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize))], spacing: 10) {
                            ForEach(currentFolderMosaics) { mosaic in
                                MosaicThumbnailView(mosaic: mosaic, size: thumbnailSize) {
                                    selectedFileId = mosaic.id
                                }
                                .id(mosaic.id)
                                
                            }.onKeyPress(phases: [.down]) { event in
                                print("key pressed")
                                if event.key == .leftArrow {
                                    handleKeyPress(.leftArrow)
                                } else if event.key == .rightArrow {
                                    handleKeyPress(.rightArrow)
                                }
                                return .handled
                            }
                            .focused($isFocused)
                                .onChange(of: selectedFileId) { newId in
                                    if let id = newId {
                                        withAnimation {
                                            proxy.scrollTo(id, anchor: .center)
                                        }
                                    }
                                }
                        }
                        .padding()
                    }.frame(minWidth: 200)

               
                }
            }
       
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 400)
        .navigationTitle(currentPath.isEmpty ? "Select a folder" : currentPath.lastPathComponent)
    }
    
    private var currentFolderMosaics: [MosaicEntry] {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("🕒 currentFolderMosaics took \(String(format: "%.3f", duration))s")
        }
        
        print("🔍 Filtering mosaics for folder: \(currentPath)")
        return mosaics.filter { mosaic in
            (mosaic.movieFilePath as NSString).deletingLastPathComponent == currentPath
        }
    }
    
    private func navigateUp() {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("🕒 navigateUp took \(String(format: "%.3f", duration))s")
        }
        
        print("⬆️ Navigating up from: \(currentPath)")
        currentPath = (currentPath as NSString).deletingLastPathComponent
        print("📍 New path: \(currentPath)")
    }
    
    private func folderRow(name: String, count: Int) -> some SwiftUI.View {
        Button(action: { currentPath = name }) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(name.lastPathComponent)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func fileRow(mosaic: MosaicEntry) -> some SwiftUI.View {
        Button(action: { selectedFileId = mosaic.id }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mosaic.movieFilePath.lastPathComponent)
                HStack {
                    Text(mosaic.resolution)
                    Text("•")
                    Text(mosaic.videoType)
                    Text("•")
                    Text(mosaic.formattedDuration)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }.cornerRadius(8)
    }
    
    private struct FolderItem {
        let mosaic: MosaicEntry?
        let isFolder: Bool
    }
    
    private func groupMosaicsByFolder(_ mosaics: [MosaicEntry]) -> [String: [FolderItem]] {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("🕒 groupMosaicsByFolder took \(String(format: "%.3f", duration))s")
        }
        
        print("📂 Grouping \(mosaics.count) mosaics by folder...")
        var result: [String: [FolderItem]] = [:]
        
        for mosaic in mosaics {
            let path = mosaic.movieFilePath as NSString
            let currentFolder = currentPath
            
            if path.deletingLastPathComponent.hasPrefix(currentFolder) {
                let relativePath = path.deletingLastPathComponent.replacingOccurrences(of: currentFolder, with: "")
                let components = relativePath.split(separator: "/")
                
                if components.isEmpty {
                    result[path.deletingLastPathComponent, default: []].append(FolderItem(mosaic: mosaic, isFolder: false))
                } else {
                    let nextFolder = components[0]
                    let folderPath = currentFolder.appending("/\(nextFolder)")
                    result[folderPath, default: []].append(FolderItem(mosaic: nil, isFolder: true))
                }
            }
        }
        
        print("📊 Found \(result.count) folders")
        return result
    }
    
    private func handleKeyPress(_ key: KeyEquivalent) {
        guard isFocused, let currentId = selectedFileId,
              let currentIndex = currentFolderMosaics.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        
        let columns = Int(floor(NSScreen.main?.frame.width ?? 1000 / thumbnailSize))
        var newIndex = currentIndex
        
        switch key {
        case .leftArrow:
            if currentIndex > 0 {
                print("left")
                newIndex = currentIndex - 1
            }
        case .rightArrow:
            print("right")
            if currentIndex < currentFolderMosaics.count - 1 {
                newIndex = currentIndex + 1
            }
        case .upArrow:
            print("up")
            if currentIndex >= columns {
                newIndex = currentIndex - columns
            }
        case .downArrow:
            print("down")
            if currentIndex + columns < currentFolderMosaics.count {
                newIndex = currentIndex + columns
            }
        default:
            break
        }
        
        if newIndex != currentIndex {
            selectedFileId = currentFolderMosaics[newIndex].id
        }
    }
}

struct MosaicThumbnailView: SwiftUI.View {
    let mosaic: MosaicEntry
    let size: CGFloat
    let action: () -> Void
    
    var body: some SwiftUI.View {
        Button(action: action) {
            VStack {
                if let image = NSImage(contentsOf: URL(fileURLWithPath: mosaic.mosaicFilePath)) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
                
                Text(mosaic.movieFilePath.lastPathComponent)
                    .lineLimit(1)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}



extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
    
}

extension MosaicEntry {
    var folderPath: String {
        (self.movieFilePath as NSString).deletingLastPathComponent
    }
}

extension MosaicEntry {
    var realResolution: String {
        String("\(Int(self.resolutionWidth)) x \(Int(self.resolutionHeight))")
    }
}

struct FilterMenu: SwiftUI.View {
    let title: String
    @SwiftUI.Binding var selection: String
    let options: [String]
    
    var body: some SwiftUI.View {
        Menu {
            Button("All") {
                selection = ""
            }
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option
                }
            }
        } label: {
            HStack {
                //Text(title)
                Text(selection.isEmpty ? "All" : selection)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// Create a new struct for the version picker
struct MosaicVersionPicker: SwiftUI.View {
    let currentFile: MosaicEntry
    var alternativeVersions: [MosaicEntry]
    @SwiftUI.Binding var selectedVersion: MosaicEntry?
    
    var body: some SwiftUI.View {
        let allVersions = [currentFile] + alternativeVersions
            .filter { $0.id != currentFile.id } // Ensure no duplicates
            .sorted { $0.size < $1.size } // Sort by size for better organization
        
        Picker("Version", selection: $selectedVersion) {
            ForEach(allVersions) { version in
                HStack {
                    Text("\(version.size)px - \(version.density)")
                }
                .tag(version as MosaicEntry?)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .onChange(of: selectedVersion) { newVersion in
            print("Selected version changed to: \(newVersion?.size ?? "none")")
        }
    }
}

// Create a new struct for the navigation buttons
struct MosaicNavigationButtons: SwiftUI.View {
    let hasPreviousMosaic: Bool
    let hasNextMosaic: Bool
    let navigateToPrevious: () -> Void
    let navigateToNext: () -> Void
    @SwiftUI.FocusState.Binding var isFocused: Bool
    
    var body: some SwiftUI.View {
        HStack {
            Button(action: navigateToPrevious) {
                Label("Previous", systemImage: "chevron.left.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .buttonStyle(.plain)
            .disabled(!hasPreviousMosaic)
            .keyboardShortcut(.leftArrow, modifiers: [])
            
            Spacer()
            
            Button(action: navigateToNext) {
                Label("Next", systemImage: "chevron.right.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .buttonStyle(.plain)
            .disabled(!hasNextMosaic)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal)
    }
}

// Create a new struct for the action buttons
struct MosaicActionButtons: SwiftUI.View {
    let currentFile: MosaicEntry
    
    var body: some SwiftUI.View {
        HStack {
            Button(action: {
                openInIINA(sourceFile: currentFile.movieFilePath)
            }) {
                Label("Play in IINA", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            Button(action: {
                NSWorkspace.shared.open(URL(fileURLWithPath: currentFile.folderPath))
            }) {
                Label("Show in Finder", systemImage: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
            }
        }
    }
    
    private func openInIINA(sourceFile: String) {
        let url = URL(fileURLWithPath: sourceFile)
        let iinaURL = URL(string: "iina://open?url=\(url.path)")!
        NSWorkspace.shared.open(iinaURL)
    }
}

// Simplified MosaicNavigatorDetailView
struct MosaicNavigatorDetailView: SwiftUI.View {
    let file: MosaicEntry?
    @State private var alternativeVersions: [MosaicEntry] = []
    @State private var selectedVersion: MosaicEntry?
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool
    @ObservedObject var viewModel: MosaicViewModel
    
    var body: some SwiftUI.View {
        VStack {
            if let currentFile = selectedVersion ?? file {
                if !alternativeVersions.isEmpty {
                    MosaicVersionPicker(
                        currentFile: currentFile,
                        alternativeVersions: alternativeVersions,
                        selectedVersion: $selectedVersion
                    )
                }
                
                if let image = NSImage(contentsOf: URL(fileURLWithPath: currentFile.mosaicFilePath)) {
                    MosaicNavigationButtons(
                        hasPreviousMosaic: hasPreviousMosaic,
                        hasNextMosaic: hasNextMosaic,
                        navigateToPrevious: navigateToPrevious,
                        navigateToNext: navigateToNext,
                        isFocused: $isFocused
                    )
                    
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .focused($isFocused)
                    
                    MosaicActionButtons(currentFile: currentFile)
                }
            } else {
                Text("Select a file to view its mosaic")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? viewModel.currentTheme.colors.primary : Color.gray.opacity(0.3), 
                       lineWidth: isHovered ? 2 : 1)
        )
        .background(Color.clear)
        .navigationTitle("Mosaic Preview")
        .onChange(of: file) { newFile in
            let start = CFAbsoluteTimeGetCurrent()
            if let newFile = newFile {
                print("🔄 Loading alternative versions for: \(newFile.movieFilePath.lastPathComponent)")
                selectedVersion = nil // Reset selection when file changes
                alternativeVersions = DatabaseManager.shared.fetchAlternativeVersions(for: newFile)
                 //   .filter { $0.id != newFile.id } // Ensure current file is not in alternatives
                print("📊 Found \(alternativeVersions.count) alternative versions")
                let duration = CFAbsoluteTimeGetCurrent() - start
                print("🕒 Alternative versions loading took \(String(format: "%.3f", duration))s")
            } else {
                selectedVersion = nil
                alternativeVersions = []
            }
        }
    }
    
    private func openInIINA(sourceFile: String) {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            print("🕒 openInIINA took \(String(format: "%.3f", duration))s")
        }
        
        print("🎬 Opening in IINA: \(sourceFile)")
        let url = URL(fileURLWithPath: sourceFile)
        let iinaURL = URL(string: "iina://open?url=\(url.path)")!
        NSWorkspace.shared.open(iinaURL)
    }
    
    private func handleKeyPress(_ key: KeyEquivalent) {
        guard isFocused else { return }
        print("🔄 Handling key press: \(key)")
        switch key {
        case .leftArrow:
            if let currentVersion = selectedVersion,
               let index = alternativeVersions.firstIndex(of: currentVersion),
               index > 0 {
                selectedVersion = alternativeVersions[index - 1]
            }
        case .rightArrow:
            if let currentVersion = selectedVersion,
               let index = alternativeVersions.firstIndex(of: currentVersion),
               index < alternativeVersions.count - 1 {
                selectedVersion = alternativeVersions[index + 1]
            }
        default:
            break
        }
    }
    
    private var hasPreviousMosaic: Bool {
        guard let currentFile = file,
              let index = viewModel.allMosaics.firstIndex(where: { $0.id == currentFile.id }) else {
            return false
        }
        return index > 0
    }
    
    private var hasNextMosaic: Bool {
        guard let currentFile = file,
              let index = viewModel.allMosaics.firstIndex(where: { $0.id == currentFile.id }) else {
            return false
        }
        return index < viewModel.allMosaics.count - 1
    }
    
    private func navigateToNext() {
        guard let currentFile = file,
              let currentIndex = viewModel.allMosaics.firstIndex(where: { $0.id == currentFile.id }),
              currentIndex < viewModel.allMosaics.count - 1 else {
            return
        }
        print("🔄 Navigating to next mosaic: \(currentIndex + 1)")
        let nextMosaic = viewModel.allMosaics[currentIndex + 1]
        NotificationCenter.default.post(
            name: Notification.Name("SelectMosaicEntry"),
            object: nil,
            userInfo: ["mosaicId": nextMosaic.id]
        )
    }
    
    private func navigateToPrevious() {
        guard let currentFile = file,
              let currentIndex = viewModel.allMosaics.firstIndex(where: { $0.id == currentFile.id }),
              currentIndex > 0 else {
            return
        }
        print("🔄 Navigating to previous mosaic: \(currentIndex - 1)")
        let previousMosaic = viewModel.allMosaics[currentIndex - 1]
        NotificationCenter.default.post(
            name: Notification.Name("SelectMosaicEntry"),
            object: nil,
            userInfo: ["mosaicId": previousMosaic.id]
        )
    }
}

struct VersionButton: SwiftUI.View {
    let size: String
    let density: String
    let isSelected: Bool
    var action: (() -> Void)? = nil
    
    var body: some SwiftUI.View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Text("\(size)px")
                Text("•")
                Text(density)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// Add this view for the variant settings
struct MosaicVariantSettingsView: SwiftUI.View {
    @ObservedObject var viewModel: MosaicViewModel
    @Environment(\.dismiss) private var dismiss
    let moviePath: String
    
    var body: some SwiftUI.View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Reuse existing settings from EnhancedMosaicSettings
                    // Size Selection
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
                            
                            // Density Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Density", systemImage: "chart.bar.fill")
                                    .foregroundStyle(viewModel.currentTheme.colors.primary)
                                Slider(value: $viewModel.selectedDensity, in: 1...7, step: 1)
                            }
                        }
                    }
                    
                    // Format Settings
                    SettingsCard(title: "Format", icon: "doc.fill", viewModel: viewModel) {
                        FormatPicker(selection: $viewModel.selectedFormat)
                    }
                }
                .padding()
            }
            .navigationTitle("New Variant Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        Task {
                            await viewModel.generateVariant(for: moviePath)
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 800)
        .navigationViewStyle(.columns)
    }
}

    #Preview {
        MosaicNavigatorView(viewModel: MosaicViewModel())
            .frame(width: 2000, height: 1000)
    }

    
