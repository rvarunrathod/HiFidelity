//
//  EntityDetailView.swift
//  HiFidelity
//
//  Generic detail view for Albums, Artists, Genres, and Playlists
//

import SwiftUI

/// Generic entity detail view showing tracks
struct EntityDetailView: View {
    let entity: EntityType
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    
    @State private var tracks: [Track] = []
    @State private var filteredTracks: [Track] = []
    @State private var sortedTracks: [Track] = []
    @State private var isLoading = false
    @State private var selectedTrack: Track.ID?
    @State private var sortOrder = [KeyPathComparator(\Track.title, order: .forward)]
    @State private var selectedFilter: TrackFilter?
    
    // Sorting persistence - separate storage for each entity type
    @AppStorage("albumDetailSortField") private var albumSortField: String = "title"
    @AppStorage("albumDetailSortAscending") private var albumSortAscending: Bool = true
    @AppStorage("artistDetailSortField") private var artistSortField: String = "title"
    @AppStorage("artistDetailSortAscending") private var artistSortAscending: Bool = true
    @AppStorage("genreDetailSortField") private var genreSortField: String = "title"
    @AppStorage("genreDetailSortAscending") private var genreSortAscending: Bool = true
    @AppStorage("playlistDetailSortField") private var playlistSortField: String = "title"
    @AppStorage("playlistDetailSortAscending") private var playlistSortAscending: Bool = true
    
    // Helper computed properties for current entity's sort storage
    private var currentSortField: Binding<String> {
        switch entity {
        case .album: return $albumSortField
        case .artist: return $artistSortField
        case .genre: return $genreSortField
        case .playlist: return $playlistSortField
        }
    }
    
    private var currentSortAscending: Binding<Bool> {
        switch entity {
        case .album: return $albumSortAscending
        case .artist: return $artistSortAscending
        case .genre: return $genreSortAscending
        case .playlist: return $playlistSortAscending
        }
    }
    
    // Playlist context for remove functionality
    private var playlistContext: NSTrackTableView.PlaylistContext? {
        guard case .playlist(let playlist) = entity, !playlist.isSmart else {
            return nil
        }
        return NSTrackTableView.PlaylistContext(
            playlist: playlist,
            onRemove: {
                Task { await loadTracks() }
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Entity header
            EntityHeader(
                entity: entity,
                trackCount: sortedTracks.count,
                totalDuration: calculateTotalDuration(),
                onPlay: playAll,
                onShuffle: shuffleAll
            )
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 12) {
                    TrackTableOptionsDropdown(
                        sortOrder: $sortOrder,
                        selectedFilter: $selectedFilter
                    )
                    .frame(width: 32)
                }
                .padding([.bottom, .trailing], 12)
            }
            
            // Tracks list
            if isLoading {
                loadingView
            } else if sortedTracks.isEmpty {
                emptyStateView
            } else {
                tracksList
            }
        }
        .id(entity.uniqueId) // Force view recreation when entity changes
        .task(id: entity.uniqueId) { // Reload tracks when entity changes
            // Restore saved sort order for this entity type
            restoreSortOrder()
            await loadTracks()
        }
        .onChange(of: sortOrder) { oldValue, newValue in
            if oldValue != newValue {
                saveSortOrder(newValue)
                performBackgroundSort(with: newValue)
            }
        }
        .onChange(of: tracks) { _, newTracks in
            if !newTracks.isEmpty {
                applyFilter()
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            applyFilter()
        }
    }
    
    // MARK: - Tracks List
    
    private var tracksList: some View {
        TrackTableView(
            tracks: sortedTracks,
            selection: $selectedTrack,
            sortOrder: $sortOrder,
            onPlayTrack: playTrack,
            isCurrentTrack: isCurrentTrack,
            playlistContext: playlistContext
        )
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(theme.currentTheme.primaryColor)
                
                Text("Loading tracks...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: entity.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No tracks found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("This \(entity.displayName.lowercased()) has no tracks")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func isCurrentTrack(_ track: Track) -> Bool {
        guard let currentTrack = playback.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }
    
    private func playTrack(_ track: Track) {
        guard let trackIndex = sortedTracks.firstIndex(where: { $0.id == track.id }) else {
            playback.playTracks([track], startingAt: 0)
            return
        }
        
        playback.playTracks(sortedTracks, startingAt: trackIndex)
    }
    
    private func playAll() {
        playback.playTracks(sortedTracks)
    }
    
    private func shuffleAll() {
        playback.playTracksShuffled(sortedTracks)
    }
    
    private func calculateTotalDuration() -> Double {
        sortedTracks.reduce(0) { $0 + ($1.duration) }
    }
    
    // MARK: - Data Loading
    
    private func loadTracks() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            tracks = try await entity.loadTracks(from: databaseManager)
        } catch {
            Logger.error("Failed to load tracks for \(entity.displayName): \(error)")
        }
    }
    
    // MARK: - Filtering
    
    private func applyFilter() {
        if let filter = selectedFilter {
            switch filter {
            case .favorites:
                filteredTracks = tracks.filter { $0.isFavorite }
            case .recentlyAdded:
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                filteredTracks = tracks.filter { 
                    guard let dateAdded = $0.dateAdded else { return false }
                    return dateAdded >= thirtyDaysAgo
                }
            case .unplayed:
                filteredTracks = tracks.filter { $0.playCount == 0 }
            }
        } else {
            filteredTracks = tracks
        }
        
        // Re-sort after filtering
        initializeSortedTracks()
    }
    
    // MARK: - Sorting Helpers
    
    private func initializeSortedTracks() {
        // Use current sort order instead of resetting to default
        sortedTracks = filteredTracks.sorted(using: sortOrder)
    }
    
    private func performBackgroundSort(with newSortOrder: [KeyPathComparator<Track>]) {
        let tracksToSort = self.filteredTracks
        Task.detached(priority: .userInitiated) {
            let sorted = tracksToSort.sorted(using: newSortOrder)
            await MainActor.run {
                self.sortedTracks = sorted
            }
        }
    }
    
    // MARK: - Sort Order Persistence
    
    private func restoreSortOrder() {
        let field = currentSortField.wrappedValue
        let isAscending = currentSortAscending.wrappedValue
        
        if let sortField = TrackSortField.allFields.first(where: { $0.rawValue == field }) {
            sortOrder = [sortField.getComparator(ascending: isAscending)]
        }
    }
    
    private func saveSortOrder(_ sortOrder: [KeyPathComparator<Track>]) {
        guard let firstSort = sortOrder.first else { return }
        
        let sortString = String(describing: firstSort)
        let isAscending = sortString.contains("forward")
        
        // Map comparator to field
        let sortKeyMap: [String: TrackSortField] = [
            "title": .title,
            "artist": .artist,
            "album": .album,
            "genre": .genre,
            "year": .year,
            "duration": .duration,
            "playCount": .playCount,
            "codec": .codec,
            "dateAdded": .dateAdded,
            "filename": .filename,
            "trackNumber": .trackNumber,
            "discNumber": .discNumber,
        ]
        
        for (key, field) in sortKeyMap {
            if sortString.contains(key) {
                currentSortField.wrappedValue = field.rawValue
                currentSortAscending.wrappedValue = isAscending
                break
            }
        }
    }
}

// MARK: - Entity Type

enum EntityType: Identifiable, Hashable {
    case album(Album)
    case artist(Artist)
    case genre(Genre)
    case playlist(PlaylistItem)
    
    var id: String {
        switch self {
        case .album(let album): return "album_\(album.id ?? 0)"
        case .artist(let artist): return "artist_\(artist.id ?? 0)"
        case .genre(let genre): return "genre_\(genre.id ?? 0)"
        case .playlist(let playlist): return "playlist_\(playlist.id)"
        }
    }
    
    var uniqueId: String { id }
    
    var displayName: String {
        switch self {
        case .album(let album): return album.title
        case .artist(let artist): return artist.name
        case .genre(let genre): return genre.name
        case .playlist(let playlist): return playlist.name
        }
    }
    
    var icon: String {
        switch self {
        case .album: return "square.stack"
        case .artist: return "person.2"
        case .genre: return "guitars"
        case .playlist(let playlist): return playlist.icon
        }
    }
    
    var subtitle: String? {
        switch self {
        case .album(let album): return album.year
        case .artist(_): return nil
        case .genre(_): return nil
        case .playlist(let playlist):
            if case .smart(let smartType) = playlist.type {
                return smartType.description
            }
            return nil
        }
    }
    
    var artworkData: Data? {
        switch self {
        case .album(let album): return album.artworkData
        case .artist: return nil
        case .genre: return nil
        case .playlist(let playlist): return playlist.artworkData
        }
    }
    
    var entityId: Int64? {
        switch self {
        case .album(let album): return album.id
        case .artist(let artist): return artist.id
        case .genre(let genre): return genre.id
        case .playlist(let playlist):
            if case .user(let p) = playlist.type {
                return p.id
            }
            return nil
        }
    }
    
    var isPinned: Bool {
        switch self {
        case .album, .artist, .genre: return false
        case .playlist(let playlist): return playlist.isPinned
        }
    }
    
    var colorScheme: String? {
        switch self {
        case .album, .artist, .genre: return nil
        case .playlist(let playlist):
            if case .user(let p) = playlist.type {
                return p.colorScheme
            }
            return nil
        }
    }
    
    var badgeText: String {
        switch self {
        case .album: return "ALBUM"
        case .artist: return "ARTIST"
        case .genre: return "GENRE"
        case .playlist(let playlist):
            if case .smart = playlist.type {
                return "SMART PLAYLIST"
            }
            return "PLAYLIST"
        }
    }
    
    var badgeIcon: String {
        switch self {
        case .album: return "square.stack"
        case .artist: return "person.2"
        case .genre: return "guitars"
        case .playlist(let playlist):
            if case .smart(let smartType) = playlist.type {
                return smartType.icon
            }
            return "music.note.list"
        }
    }
    
    func loadTracks(from database: DatabaseManager) async throws -> [Track] {
        switch self {
        case .album(let album):
            guard let albumId = album.id else { return [] }
            return try await database.getTracksForAlbum(albumId: albumId)
            
        case .artist(let artist):
            guard let artistId = artist.id else { return [] }
            return try await database.getTracksForArtist(artistId: artistId)
            
        case .genre(let genre):
            guard let genreId = genre.id else { return [] }
            return try await database.getTracksForGenre(genreId: genreId)
            
        case .playlist(let playlist):
            switch playlist.type {
            case .user(let p):
                guard let playlistId = p.id else { return [] }
                return try await database.getTracksForPlaylist(playlistId: playlistId)
                
            case .smart(let smartType):
                switch smartType {
                case .favorites:
                    return try await database.getFavoriteTracks()
                case .topPlayed:
                    return try await database.getTopPlayedTracks(limit: 25)
                case .recentlyPlayed:
                    return try await database.getRecentlyPlayedTracks(limit: 25)
                }
            }
        }
    }
}

// MARK: - Entity Header

struct EntityHeader: View {
    let entity: EntityType
    let trackCount: Int
    let totalDuration: Double
    let onPlay: () -> Void
    let onShuffle: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isPlayHovered = false
    @State private var isShuffleHovered = false
    
    var body: some View {
        HStack(spacing: 40) {
            // Artwork
            artworkView
                .padding(.leading, 12)
            
            // Info and controls
            VStack(alignment: .leading, spacing: 16) {
                // Entity badge
                HStack(spacing: 6) {
                    Image(systemName: entity.badgeIcon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(entity.badgeText)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(entity.isPinned ? theme.currentTheme.primaryColor : .secondary)
                
                // Entity name
                Text(entity.displayName)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Subtitle and stats
                VStack(alignment: .leading, spacing: 4) {
                    
                    HStack(spacing: 8) {
                        if entity.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 12))
                                .foregroundColor(theme.currentTheme.primaryColor)
                        }
                        
                        if let subtitle = entity.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        
                        Text("\(trackCount) \(trackCount == 1 ? "song" : "songs")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if totalDuration > 0 {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text(formatDuration(totalDuration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    // Play button
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .bold))

                            Text("Play")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(isPlayHovered ? theme.currentTheme.primaryColor.opacity(0.9) : theme.currentTheme.primaryColor)
                        )
                        .scaleEffect(isPlayHovered ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isPlayHovered = hovering
                    }
                    .disabled(trackCount == 0)
                    
                    // Shuffle button
                    Button(action: onShuffle) {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14, weight: .bold))
                            Text("Shuffle")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(isShuffleHovered ? Color(nsColor: .controlBackgroundColor).opacity(0.8) : Color(nsColor: .controlBackgroundColor))
                        )
                        .scaleEffect(isShuffleHovered ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isShuffleHovered = hovering
                    }
                    .disabled(trackCount == 0)
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding(20)
        .background(.regularMaterial)
//        .background(gradientBackground)
        .textSelection(.enabled)
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private var artworkView: some View {
        ZStack {
            if let imageData = entity.artworkData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 160)
                    .cornerRadius(entity.isArtist ? 100 : 12)
                    .shadow(radius: 20)
            } else if entity.isArtist, let artistId = entity.entityId {
                ArtistArtworkView(artistId: artistId, size: 160)
                    .shadow(radius: 20)
            } else if entity.isAlbum, let albumId = entity.entityId {
                AlbumArtworkView(albumId: albumId, size: 160, cornerRadius: 12)
                    .shadow(radius: 20)
            } else {
                placeholderArtwork
            }
        }
        .id(entity.id) // Stabilize artwork view
    }
    
    private var placeholderArtwork: some View {
        Group {
            if entity.isArtist {
                Circle()
                    .fill(entityGradient)
                    .frame(width: 160, height: 160)
                    .overlay {
                        Image(systemName: entity.icon)
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .shadow(radius: 20)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(entityGradient)
                    .frame(width: 160, height: 160)
                    .overlay {
                        Image(systemName: entity.icon)
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .shadow(radius: 20)
            }
        }
    }
    
    private var entityGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.currentTheme.primaryColor.opacity(0.8),
                theme.currentTheme.primaryColor.opacity(0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var gradientBackground: some View {
        LinearGradient(
            colors: [
                theme.currentTheme.primaryColor.opacity(0.15),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
}

// MARK: - Entity Type Helpers

extension EntityType {
    var isAlbum: Bool {
        if case .album = self { return true }
        return false
    }
    
    var isArtist: Bool {
        if case .artist = self { return true }
        return false
    }
    
    var isGenre: Bool {
        if case .genre = self { return true }
        return false
    }
    
    var isPlaylist: Bool {
        if case .playlist = self { return true }
        return false
    }
}

// MARK: - Convenience Wrapper

/// Playlist detail view using generic EntityDetailView
struct PlaylistDetailView: View {
    let playlist: PlaylistItem
    
    var body: some View {
        EntityDetailView(entity: .playlist(playlist))
    }
}

