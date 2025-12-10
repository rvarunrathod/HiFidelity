//
//  ArtistsTabView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Artists tab view displaying all artists in a grid layout
struct ArtistsTabView: View {
    @Binding var selectedEntity: EntityType?
    let isVisible: Bool
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    
    @State private var artists: [Artist] = []
    @State private var filteredArtists: [Artist] = []
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
        SortOption(id: "albums", title: "Album Count", type: .albumCount, ascending: false),
        SortOption(id: "tracks", title: "Track Count", type: .trackCount, ascending: false)
    ]
    
    private let filterOptions = [
        FilterOption(id: "10plus", title: "10+ Tracks", predicate: "trackCount >= 10"),
        FilterOption(id: "5plus", title: "5+ Tracks", predicate: "trackCount >= 5"),
        FilterOption(id: "multialbum", title: "Multiple Albums", predicate: "albumCount > 1")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if filteredArtists.isEmpty {
                if artists.isEmpty {
                    emptyStateView(icon: "person.2", message: "No artists in library")
                } else {
                    emptyStateView(icon: "line.3.horizontal.decrease.circle", message: "No artists match your filter")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
                    ], spacing: 20) {
                        ForEach(Array(filteredArtists.enumerated()), id: \.element.id) { index, artist in
                            ArtistCard(artist: artist) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedEntity = .artist(artist)
                                }
                            }
                            .onAppear {
                                // Prefetch artwork for upcoming artists
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
                    await loadArtists()
                    hasLoadedOnce = true
                }
            }
        }
        .onAppear {
            if isVisible && !hasLoadedOnce {
                Task {
                    await loadArtists()
                    hasLoadedOnce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshLibraryData)) { _ in
            Task {
                await loadArtists()
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
                
                Text("Loading artists...")
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
            Text("\(filteredArtists.count) artists")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Sort and Filter dropdown
            ArtistOptionsDropdown(
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
    
    private func loadArtists() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            artists = try await databaseManager.getAllArtists()
            applyFiltersAndSort()
            
            // Preload artwork for initially visible artists
            Task {
                let visibleCount = min(20, filteredArtists.count)
                let visibleArtistIds = filteredArtists.prefix(visibleCount).compactMap { $0.id }
                for artistId in visibleArtistIds {
                    ArtworkCache.shared.getArtistArtwork(for: artistId, size: 160) { _ in }
                }
            }
        } catch {
            Logger.error("Failed to load artists: \(error)")
        }
    }
    
    private func applyFiltersAndSort() {
        var result = artists
        
        // Apply count filters
        if let filter = selectedFilter {
            switch filter.id {
            case "10plus":
                result = result.filter { $0.trackCount >= 10 }
            case "5plus":
                result = result.filter { $0.trackCount >= 5 }
            case "multialbum":
                result = result.filter { $0.albumCount > 1 }
            default:
                break
            }
        }
        
        // Apply sort
        switch selectedSort.type {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .albumCount:
            result.sort { $0.albumCount > $1.albumCount }
        case .trackCount:
            result.sort { $0.trackCount > $1.trackCount }
        default:
            break
        }
        
        if !selectedSort.ascending {
            result.reverse()
        }
        
        filteredArtists = result
    }
    
    // MARK: - Prefetching
    
    private func prefetchArtwork(startingAt index: Int) {
        // Prefetch next 15 artists' artwork
        let endIndex = min(index + 15, filteredArtists.count)
        guard endIndex > index else { return }
        
        let artistIds = filteredArtists[index..<endIndex].compactMap { $0.id }
        
        // Prefetch artist artwork (Note: artists may not have artwork, handled gracefully)
        for artistId in artistIds {
            ArtworkCache.shared.getArtistArtwork(for: artistId, size: 160) { _ in }
        }
    }
}

// MARK: - Artist Options Dropdown

private struct ArtistOptionsDropdown: View {
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

