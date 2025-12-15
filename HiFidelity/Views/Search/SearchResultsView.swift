//
//  SearchResultsView.swift
//  HiFidelity
//
//  Search results view with categorized results
//

import SwiftUI

struct SearchResultsView: View {
    let searchQuery: String
    @Binding var selectedEntity: EntityType?
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    
    @State private var results = DatabaseManager.SearchResults()
    @State private var isLoading = false
    @State private var selectedCategory: SearchCategory = .all
    @State private var searchMode: DatabaseManager.SearchMode = .and
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header with mode toggle
            searchHeader
            
            Divider()
            
            // Category filters
            categoryFilters
            
            Divider()
            
            // Results content
            if isLoading {
                loadingView
            } else if results.isEmpty {
                emptyStateView
            } else {
                resultsContent
            }
        }
        .textSelection(.enabled)
        .task(id: searchQuery) {
            await performSearch()
        }
        .onChange(of: searchMode) { _, _ in
            // Already handled in the picker onChange above, but keeping this
            // for consistency if searchMode changes from elsewhere
        }
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Search Results")
                        .font(.system(size: 24, weight: .bold))
                    
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .help("Search tips:\n• Results ranked by relevance (title > artist > album)\n• Use quotes for exact phrases: \"dark side\"\n• Prefix matching: \"beat\" matches \"beatles\"\n• Acronyms: \"BYOB\" matches \"B.Y.O.B\"\n• Combine terms: \"BYOB system\" for better results\n• Match All: all words must match\n• Match Any: broader results")
                }
                
                if !results.isEmpty {
                    Text("\(results.totalCount) results for \"\(searchQuery)\"")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Search mode toggle
            Picker("", selection: $searchMode) {
                Text("Match All").tag(DatabaseManager.SearchMode.and)
                Text("Match Any").tag(DatabaseManager.SearchMode.or)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .help(searchMode == .and ? 
                  "Match ALL words (exact search)" : 
                  "Match ANY word (broader results)")
            .onChange(of: searchMode) { _, _ in
                Task {
                    await performSearch()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Category Filters
    
    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategory.allCases) { category in
                    CategoryButton(
                        category: category,
                        count: categoryCount(category),
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Results Content
    
    private var resultsContent: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: []) {
                if selectedCategory == .all || selectedCategory == .tracks {
                    if !results.tracks.isEmpty {
                        resultSection(
                            title: "Tracks",
                            icon: "music.note",
                            count: results.tracks.count
                        ) {
                            tracksSection
                        }
                    }
                }
                
                if selectedCategory == .all || selectedCategory == .albums {
                    if !results.albums.isEmpty {
                        resultSection(
                            title: "Albums",
                            icon: "square.stack",
                            count: results.albums.count
                        ) {
                            albumsSection
                        }
                    }
                }
                
                if selectedCategory == .all || selectedCategory == .artists {
                    if !results.artists.isEmpty {
                        resultSection(
                            title: "Artists",
                            icon: "person.2",
                            count: results.artists.count
                        ) {
                            artistsSection
                        }
                    }
                }
                
                if selectedCategory == .all || selectedCategory == .genres {
                    if !results.genres.isEmpty {
                        resultSection(
                            title: "Genres",
                            icon: "guitars",
                            count: results.genres.count
                        ) {
                            genresSection
                        }
                    }
                }
                
                if selectedCategory == .all || selectedCategory == .playlists {
                    if !results.playlists.isEmpty {
                        resultSection(
                            title: "Playlists",
                            icon: "music.note.list",
                            count: results.playlists.count
                        ) {
                            playlistsSection
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Result Sections
    
    @ViewBuilder
    private func resultSection<Content: View>(
        title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.currentTheme.primaryColor)
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                
                Text("(\(count))")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            content()
        }
    }
    
    private var tracksSection: some View {
        VStack(spacing: 0) {
            ForEach(results.tracks.prefix(10)) { track in
                TrackSearchRow(track: track) {
                    playback.playTracks([track], startingAt: 0)
                }
                
                if track.id != results.tracks.prefix(10).last?.id {
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var albumsSection: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(results.albums.prefix(8)) { album in
                AlbumCard(album: album) {
                    selectedEntity = .album(album)
                }
            }
        }
    }
    
    private var artistsSection: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(results.artists.prefix(8)) { artist in
                ArtistCard(artist: artist) {
                    selectedEntity = .artist(artist)
                }
            }
        }
    }
    
    private var genresSection: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(results.genres.prefix(8)) { genre in
                GenreCard(genre: genre) {
                    selectedEntity = .genre(genre)
                }
            }
        }
    }
    
    private var playlistsSection: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
        ], spacing: 16) {
            ForEach(results.playlists.prefix(8)) { playlist in
                PlaylistSearchCard(playlist: playlist) {
                    let playlistItem = PlaylistItem(
                        id: "user_\(playlist.id ?? 0)",
                        name: playlist.name,
                        isPinned: playlist.isFavorite,
                        type: .user(playlist)
                    )
                    selectedEntity = .playlist(playlistItem)
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(theme.currentTheme.primaryColor)
            
            Text("Searching...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No results found")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Try a different search term")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func categoryCount(_ category: SearchCategory) -> Int {
        switch category {
        case .all:
            return results.totalCount
        case .tracks:
            return results.tracks.count
        case .albums:
            return results.albums.count
        case .artists:
            return results.artists.count
        case .genres:
            return results.genres.count
        case .playlists:
            return results.playlists.count
        }
    }
    
    private func performSearch() async {
        guard !searchQuery.isEmpty else {
            results = DatabaseManager.SearchResults()
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Use selected search mode
            results = try await databaseManager.search(query: searchQuery, mode: searchMode)
            Logger.info("Search completed (\(searchMode == .and ? "AND" : "OR") mode): \(results.totalCount) total results")
        } catch {
            Logger.error("Search failed: \(error)")
            
            results = DatabaseManager.SearchResults()
        }
    }
    
}

// MARK: - Track Search Row

struct TrackSearchRow: View {
    let track: Track
    let onPlay: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            TrackArtworkView(track: track, size: 48, cornerRadius: 6)
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                
                Text("\(track.artist) • \(track.album)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Duration
            Text(formatDuration(track.duration))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            // Play button
            if isHovered {
                Button {
                    onPlay()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(theme.currentTheme.primaryColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .textSelection(.enabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onPlay()
        }
        .contextMenu {
            TrackContextMenu(track: track)
        }
    }
}

// MARK: - Playlist Search Card

struct PlaylistSearchCard: View {
    let playlist: Playlist
    let onSelect: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.currentTheme.primaryColor.opacity(0.3),
                                theme.currentTheme.primaryColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Image(systemName: "music.note.list")
                    .font(.system(size: 40))
                    .foregroundColor(theme.currentTheme.primaryColor)
            }
            .aspectRatio(1, contentMode: .fit)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                Text("\(playlist.trackCount) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: SearchCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(category.title)
                    .font(.system(size: 13, weight: .medium))
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? theme.currentTheme.primaryColor : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Category

enum SearchCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case tracks = "Tracks"
    case albums = "Albums"
    case artists = "Artists"
    case genres = "Genres"
    case playlists = "Playlists"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
}

// MARK: - Helper Function

private func formatDuration(_ duration: Double) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

