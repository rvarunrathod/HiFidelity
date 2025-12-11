//
//  AlbumsTabView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Albums tab view displaying all albums in a grid layout
struct AlbumsTabView: View {
    @Binding var selectedEntity: EntityType?
    let isVisible: Bool
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    
    @State private var albums: [Album] = []
    @State private var filteredAlbums: [Album] = []
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var selectedSort = SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true)
    @State private var selectedFilter: FilterOption? = nil
    
    init(selectedEntity: Binding<EntityType?>, isVisible: Bool = true) {
        self._selectedEntity = selectedEntity
        self.isVisible = isVisible
    }
    

    
    private let sortOptions = [
        SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true),
        SortOption(id: "artist", title: "Artist", type: .alphabetical, ascending: true),
        SortOption(id: "recent", title: "Recently Added", type: .dateAdded, ascending: false),
        SortOption(id: "tracks", title: "Track Count", type: .trackCount, ascending: false)
    ]
    
    private let filterOptions = [
        FilterOption(id: "2020s", title: "2020s", predicate: "year >= 2020"),
        FilterOption(id: "2010s", title: "2010s", predicate: "year >= 2010 AND year < 2020"),
        FilterOption(id: "2000s", title: "2000s", predicate: "year >= 2000 AND year < 2010"),
        FilterOption(id: "90s", title: "90s & Earlier", predicate: "year < 2000")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if filteredAlbums.isEmpty {
                if albums.isEmpty {
                    emptyStateView(icon: "square.stack", message: "No albums in library")
                } else {
                    emptyStateView(icon: "line.3.horizontal.decrease.circle", message: "No albums match your filter")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
                    ], spacing: 20) {
                        ForEach(Array(filteredAlbums.enumerated()), id: \.element.id) { index, album in
                            AlbumCard(album: album) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedEntity = .album(album)
                                }
                            }
                            .onAppear {
                                // Prefetch artwork for upcoming albums
                                prefetchArtwork(startingAt: index)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue && !hasLoadedOnce {
                Task {
                    await loadAlbums()
                    hasLoadedOnce = true
                }
            }
        }
        .onAppear {
            if isVisible && !hasLoadedOnce {
                Task {
                    await loadAlbums()
                    hasLoadedOnce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshLibraryData)) { _ in
            Task {
                await loadAlbums()
            }
        }
        .onChange(of: selectedSort) { _, _ in
            applyFiltersAndSort()
        }
        .onChange(of: selectedFilter) { _, _ in
            applyFiltersAndSort()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(theme.currentTheme.primaryColor)
                
                Text("Loading albums...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Count label
            Text("\(filteredAlbums.count) albums")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Sort and Filter dropdown
            AlbumOptionsDropdown(
                selectedSort: $selectedSort,
                selectedFilter: $selectedFilter,
                sortOptions: sortOptions,
                filterOptions: filterOptions
            )
            .frame(width: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 46)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func loadAlbums() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            albums = try await databaseManager.getAllAlbums()
            applyFiltersAndSort()
            
            // Preload artwork for initially visible albums
            Task {
                let visibleCount = min(20, filteredAlbums.count)
                let visibleAlbumIds = filteredAlbums.prefix(visibleCount).compactMap { $0.id }
                ArtworkCache.shared.preloadAlbumArtwork(for: visibleAlbumIds, size: 160)
            }
        } catch {
            Logger.error("Failed to load albums: \(error)")
        }
    }
    
    private func applyFiltersAndSort() {
        var result = albums
        
        // Apply decade filter
        if let filter = selectedFilter {
            switch filter.id {
            case "2020s":
                result = result.filter {
                    if let yearStr = $0.year, let year = Int(yearStr) {
                        return year >= 2020
                    }
                    return false
                }
            case "2010s":
                result = result.filter {
                    if let yearStr = $0.year, let year = Int(yearStr) {
                        return year >= 2010 && year < 2020
                    }
                    return false
                }
            case "2000s":
                result = result.filter {
                    if let yearStr = $0.year, let year = Int(yearStr) {
                        return year >= 2000 && year < 2010
                    }
                    return false
                }
            case "90s":
                result = result.filter {
                    if let yearStr = $0.year, let year = Int(yearStr) {
                        return year < 2000
                    }
                    return false
                }
            default:
                break
            }
        }
        
        // Apply sort
        switch selectedSort.type {
        case .alphabetical:
            if selectedSort.id == "artist" {
                result.sort { 
                    let artist1 = $0.albumArtist ?? ""
                    let artist2 = $1.albumArtist ?? ""
                    return artist1.localizedCompare(artist2) == .orderedAscending
                }
            } else {
                result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
            }
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .trackCount:
            result.sort { $0.trackCount > $1.trackCount }
        default:
            break
        }
        
        if !selectedSort.ascending {
            result.reverse()
        }
        
        filteredAlbums = result
    }
    
    // MARK: - Prefetching
    
    private func prefetchArtwork(startingAt index: Int) {
        // Prefetch next 15 albums' artwork
        let endIndex = min(index + 15, filteredAlbums.count)
        guard endIndex > index else { return }
        
        let albumIds = filteredAlbums[index..<endIndex].compactMap { $0.id }
        ArtworkCache.shared.preloadAlbumArtwork(for: albumIds, size: 160)
    }
}

// MARK: - Album Options Dropdown

private struct AlbumOptionsDropdown: View {
    @Binding var selectedSort: SortOption
    @Binding var selectedFilter: FilterOption?
    let sortOptions: [SortOption]
    let filterOptions: [FilterOption]
    
    @ObservedObject private var theme = AppTheme.shared
    
    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(sortOptions) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if selectedSort.id == option.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Sort order") {
                Button {
                    selectedSort = SortOption(
                        id: selectedSort.id,
                        title: selectedSort.title,
                        type: selectedSort.type,
                        ascending: true
                    )
                } label: {
                    HStack {
                        Text("Ascending")
                        if selectedSort.ascending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button {
                    selectedSort = SortOption(
                        id: selectedSort.id,
                        title: selectedSort.title,
                        type: selectedSort.type,
                        ascending: false
                    )
                } label: {
                    HStack {
                        Text("Descending")
                        if !selectedSort.ascending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Filter") {
                ForEach(filterOptions) { filter in
                    Button {
                        selectedFilter = (selectedFilter == filter) ? nil : filter
                    } label: {
                        HStack {
                            Text(filter.title)
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                if selectedFilter != nil {
                    Button("Clear Filter") {
                        selectedFilter = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .medium))
                if selectedFilter != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(theme.currentTheme.primaryColor)
                }
            }
            .foregroundColor(selectedFilter != nil ? theme.currentTheme.primaryColor : .secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(selectedFilter != nil ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

