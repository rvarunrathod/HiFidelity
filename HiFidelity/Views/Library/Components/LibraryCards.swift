//
//  LibraryCards.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

// MARK: - Shared Empty State View

func emptyStateView(icon: String, message: String) -> some View {
    VStack(spacing: 20) {
        Image(systemName: icon)
            .font(.system(size: 56, weight: .light))
            .foregroundColor(.secondary.opacity(0.35))
        
        Text(message)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary.opacity(0.8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}


// MARK: - Album Card

struct AlbumCard: View, Equatable {
    let album: Album
    let onTap: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: AlbumCard, rhs: AlbumCard) -> Bool {
        lhs.album.id == rhs.album.id &&
        lhs.album.title == rhs.album.title &&
        lhs.album.displayArtist == rhs.album.displayArtist
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Artwork
                ZStack {
                    if let albumId = album.id {
                        AlbumArtworkView(albumId: albumId, size: 160, cornerRadius: 8)
                            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.currentTheme.primaryColor.opacity(0.3))
                            .frame(width: 160, height: 160)
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    }
                    
                    if isHovered {
                        Button(action: playAlbum) {
                            Circle()
                                .fill(theme.currentTheme.primaryColor)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: theme.currentTheme.primaryColor.opacity(0.4), radius: 12, y: 4)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(width: 160, height: 160)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                
                // Info
                VStack(alignment: .leading, spacing: 5) {
                    Text(album.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .help(album.title)
                    
                    if let year = album.year {
                        Text(year)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text("\(album.trackCount.description) \(album.trackCount == 1 ? "song" : "songs")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(1)
                }
                .textSelection(.enabled)
            }
            .frame(width: 160, alignment: .leading)
        }
        .padding(8)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            AlbumContextMenu(album: album, onViewDetails: onTap)
        }
    }
    
    private func playAlbum() {
        Task {
            guard let albumId = album.id else { return }
            let databaseManager = DatabaseManager.shared
            do {
                var tracks = try await databaseManager.getTracksForAlbum(albumId: albumId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference
                let sortField = UserDefaults.standard.string(forKey: "albumDetailSortField") ?? "trackNumber"
                let sortAscending = UserDefaults.standard.bool(forKey: "albumDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    PlaybackController.shared.playTracks(tracks)
                }
            } catch {
                Logger.error("Failed to play album: \(error)")
            }
        }
    }
}

// MARK: - Artist Card

struct ArtistCard: View, Equatable {
    let artist: Artist
    let onTap: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: ArtistCard, rhs: ArtistCard) -> Bool {
        lhs.artist.id == rhs.artist.id &&
        lhs.artist.name == rhs.artist.name &&
        lhs.artist.trackCount == rhs.artist.trackCount
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .center, spacing: 10) {
                // Artwork (circular)
                ZStack {
                    if let artistId = artist.id {
                        ArtistArtworkView(artistId: artistId, size: 160)
                            .shadow(color: .black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
                    } else {
                        Circle()
                            .fill(theme.currentTheme.primaryColor.opacity(0.3))
                            .frame(width: 160, height: 160)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 54, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            )
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    }
                    
                    if isHovered {
                        Button(action: playArtist) {
                            Circle()
                                .fill(theme.currentTheme.primaryColor)
                                .frame(width: 54, height: 54)
                                .overlay(
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: theme.currentTheme.primaryColor.opacity(0.4), radius: 12, y: 4)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(width: 160, height: 160)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                
                // Info
                VStack(spacing: 5) {
                    Text(artist.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(artist.trackCount.description) \(artist.trackCount == 1 ? "song" : "songs")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.85))
                }
                .textSelection(.enabled)
            }
            .frame(width: 160, alignment: .center)
        }
        .padding(8)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            ArtistContextMenu(artist: artist, onViewDetails: onTap)
        }
    }
    
    private func playArtist() {
        Task {
            guard let artistId = artist.id else { return }
            let databaseManager = DatabaseManager.shared
            do {
                var tracks = try await databaseManager.getTracksForArtist(artistId: artistId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference
                let sortField = UserDefaults.standard.string(forKey: "artistDetailSortField") ?? "title"
                let sortAscending = UserDefaults.standard.bool(forKey: "artistDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    PlaybackController.shared.playTracks(tracks)
                }
            } catch {
                Logger.error("Failed to play artist: \(error)")
            }
        }
    }
}

// MARK: - Genre Card

struct GenreCard: View, Equatable {
    let genre: Genre
    let onTap: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: GenreCard, rhs: GenreCard) -> Bool {
        lhs.genre.id == rhs.genre.id &&
        lhs.genre.name == rhs.genre.name
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient specific to genre
                RoundedRectangle(cornerRadius: 14)
                    .fill(genreGradient)
                    .frame(height: 130)
                
                // Genre info
                VStack(alignment: .leading, spacing: 7) {
                    Text(genre.name)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    
                    Text("\(genre.trackCount) \(genre.trackCount == 1 ? "track" : "tracks")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 14 : 10, y: isHovered ? 6 : 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Genre Visual Styling
    
    private var genreGradient: LinearGradient {
        let colors = genreColorScheme
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var genreColorScheme: [Color] {
        let genreName = genre.name.lowercased()
        
        // Map genres to color schemes
        switch genreName {
        case let name where name.contains("rock"):
            return [Color(red: 0.8, green: 0.2, blue: 0.2), Color(red: 0.5, green: 0.1, blue: 0.1)]
        case let name where name.contains("jazz"):
            return [Color(red: 0.2, green: 0.3, blue: 0.6), Color(red: 0.1, green: 0.15, blue: 0.35)]
        case let name where name.contains("classical"):
            return [Color(red: 0.5, green: 0.3, blue: 0.6), Color(red: 0.3, green: 0.15, blue: 0.4)]
        case let name where name.contains("electronic") || name.contains("edm") || name.contains("techno"):
            return [Color(red: 0.0, green: 0.7, blue: 0.9), Color(red: 0.0, green: 0.4, blue: 0.6)]
        case let name where name.contains("pop"):
            return [Color(red: 0.9, green: 0.3, blue: 0.6), Color(red: 0.6, green: 0.15, blue: 0.4)]
        case let name where name.contains("hip hop") || name.contains("rap"):
            return [Color(red: 0.3, green: 0.25, blue: 0.3), Color(red: 0.15, green: 0.12, blue: 0.15)]
        case let name where name.contains("metal"):
            return [Color(red: 0.2, green: 0.2, blue: 0.2), Color(red: 0.05, green: 0.05, blue: 0.05)]
        case let name where name.contains("country"):
            return [Color(red: 0.7, green: 0.5, blue: 0.2), Color(red: 0.5, green: 0.3, blue: 0.1)]
        case let name where name.contains("blues"):
            return [Color(red: 0.1, green: 0.3, blue: 0.5), Color(red: 0.05, green: 0.15, blue: 0.3)]
        case let name where name.contains("reggae"):
            return [Color(red: 0.0, green: 0.6, blue: 0.3), Color(red: 0.0, green: 0.4, blue: 0.2)]
        case let name where name.contains("folk"):
            return [Color(red: 0.5, green: 0.6, blue: 0.3), Color(red: 0.3, green: 0.4, blue: 0.2)]
        case let name where name.contains("r&b") || name.contains("soul"):
            return [Color(red: 0.6, green: 0.2, blue: 0.4), Color(red: 0.4, green: 0.1, blue: 0.25)]
        case let name where name.contains("indie"):
            return [Color(red: 0.4, green: 0.5, blue: 0.6), Color(red: 0.2, green: 0.3, blue: 0.4)]
        case let name where name.contains("ambient") || name.contains("chill"):
            return [Color(red: 0.3, green: 0.5, blue: 0.6), Color(red: 0.15, green: 0.3, blue: 0.4)]
        case let name where name.contains("latin"):
            return [Color(red: 0.9, green: 0.4, blue: 0.2), Color(red: 0.6, green: 0.2, blue: 0.1)]
        default:
            // Generate colors based on hash of genre name for consistency
            let hash = abs(genre.name.hashValue)
            let hue = Double(hash % 360) / 360.0
            return [
                Color(hue: hue, saturation: 0.6, brightness: 0.7),
                Color(hue: hue, saturation: 0.7, brightness: 0.4)
            ]
        }
    }
    
    private var genreIcon: String {
        let genreName = genre.name.lowercased()
        
        // Map genres to appropriate SF Symbols
        switch genreName {
        case let name where name.contains("rock"):
            return "bolt.fill"
        case let name where name.contains("jazz"):
            return "music.note"
        case let name where name.contains("classical"):
            return "music.quarternote.3"
        case let name where name.contains("electronic") || name.contains("edm") || name.contains("techno"):
            return "waveform"
        case let name where name.contains("pop"):
            return "sparkles"
        case let name where name.contains("hip hop") || name.contains("rap"):
            return "mic.fill"
        case let name where name.contains("metal"):
            return "flame.fill"
        case let name where name.contains("country"):
            return "guitars.fill"
        case let name where name.contains("blues"):
            return "music.note.list"
        case let name where name.contains("reggae"):
            return "waveform.path.ecg"
        case let name where name.contains("folk"):
            return "leaf.fill"
        case let name where name.contains("r&b") || name.contains("soul"):
            return "heart.fill"
        case let name where name.contains("indie"):
            return "paintbrush.fill"
        case let name where name.contains("ambient") || name.contains("chill"):
            return "cloud.fill"
        case let name where name.contains("latin"):
            return "hifispeaker.fill"
        default:
            return "music.note"
        }
    }
}

// MARK: - Track Grid Card

struct TrackGridCard: View, Equatable {
    let track: Track
    let onPlay: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var playback = PlaybackController.shared
    @State private var isHovered = false
    
    // Implement Equatable to prevent unnecessary re-renders
    static func == (lhs: TrackGridCard, rhs: TrackGridCard) -> Bool {
        lhs.track.trackId == rhs.track.trackId &&
        lhs.track.title == rhs.track.title &&
        lhs.track.artist == rhs.track.artist
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Artwork
            ZStack {
                TrackArtworkView(track: track, size: 140, cornerRadius: 10)
                    .shadow(color: .black.opacity(isHovered ? 0.25 : 0.15), radius: isHovered ? 12 : 8, y: isHovered ? 6 : 4)
                
                // Play button overlay
                if isHovered {
                    Button(action: onPlay) {
                        Circle()
                            .fill(theme.currentTheme.primaryColor)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: theme.currentTheme.primaryColor.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(width: 140, height: 140)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            
            // Track info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.85))
                    .lineLimit(1)
            }
            .textSelection(.enabled)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            TrackContextMenu(track: track)
        }
    }
}


// MARK: - Context Menus

struct AlbumContextMenu: View {
    let album: Album
    let onViewDetails: () -> Void
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var playback = PlaybackController.shared
    
    var body: some View {
        Group {
            Button {
                playAlbum()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            
            Button {
                shuffleAlbum()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            
            Divider()
            
            Button {
                onViewDetails()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }
    
    private func playAlbum() {
        Task {
            guard let albumId = album.id else { return }
            do {
                var tracks = try await databaseManager.getTracksForAlbum(albumId: albumId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference
                let sortField = UserDefaults.standard.string(forKey: "albumDetailSortField") ?? "trackNumber"
                let sortAscending = UserDefaults.standard.bool(forKey: "albumDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    playback.playTracks(tracks)
                }
            } catch {
                Logger.error("Failed to play album: \(error)")
            }
        }
    }
    
    private func shuffleAlbum() {
        Task {
            guard let albumId = album.id else { return }
            do {
                var tracks = try await databaseManager.getTracksForAlbum(albumId: albumId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference before shuffling
                let sortField = UserDefaults.standard.string(forKey: "albumDetailSortField") ?? "trackNumber"
                let sortAscending = UserDefaults.standard.bool(forKey: "albumDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    playback.playTracksShuffled(tracks)
                }
            } catch {
                Logger.error("Failed to shuffle album: \(error)")
            }
        }
    }
}

struct ArtistContextMenu: View {
    let artist: Artist
    let onViewDetails: () -> Void
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var playback = PlaybackController.shared
    
    var body: some View {
        Group {
            Button {
                playArtist()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            
            Button {
                shuffleArtist()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            
            Divider()
            
            Button {
                onViewDetails()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }
    
    private func playArtist() {
        Task {
            guard let artistId = artist.id else { return }
            do {
                var tracks = try await databaseManager.getTracksForArtist(artistId: artistId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference
                let sortField = UserDefaults.standard.string(forKey: "artistDetailSortField") ?? "title"
                let sortAscending = UserDefaults.standard.bool(forKey: "artistDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    playback.playTracks(tracks)
                }
            } catch {
                Logger.error("Failed to play artist: \(error)")
            }
        }
    }
    
    private func shuffleArtist() {
        Task {
            guard let artistId = artist.id else { return }
            do {
                var tracks = try await databaseManager.getTracksForArtist(artistId: artistId)
                guard !tracks.isEmpty else { return }
                
                // Apply saved sorting preference before shuffling
                let sortField = UserDefaults.standard.string(forKey: "artistDetailSortField") ?? "title"
                let sortAscending = UserDefaults.standard.bool(forKey: "artistDetailSortAscending")
                
                if let field = TrackSortField.allFields.first(where: { $0.rawValue == sortField }) {
                    let comparators = field.getComparators(ascending: sortAscending)
                    tracks = tracks.sorted(using: comparators)
                }
                
                await MainActor.run {
                    playback.playTracksShuffled(tracks)
                }
            } catch {
                Logger.error("Failed to shuffle artist: \(error)")
            }
        }
    }
}

