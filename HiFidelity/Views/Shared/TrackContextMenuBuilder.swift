//
//  TrackContextMenuBuilder.swift
//  HiFidelity
//
//  Shared logic for track context menu actions
//

import Foundation
import AppKit

/// Centralized track context menu logic
/// Used by both SwiftUI context menus and NSMenu implementations
class TrackContextMenuBuilder {
    
    // MARK: - Playback Actions
    
    static func playTrack(_ track: Track) {
        PlaybackController.shared.playTracks([track], startingAt: 0)
    }
    
    static func playNext(_ track: Track) {
        PlaybackController.shared.playNext(track)
    }
    
    static func addToQueue(_ track: Track) {
        PlaybackController.shared.addToQueue(track)
    }
    
    // MARK: - Playlist Actions
    
    static func showCreatePlaylist(with track: Track) {
        guard let coordinator = AppCoordinator.shared else { return }
        coordinator.showCreatePlaylist(with: track)
    }
    
    static func addToPlaylist(_ track: Track, playlist: Playlist) {
        guard let playlistId = playlist.id,
              let trackId = track.trackId else { return }
        
        Task {
            do {
                try await DatabaseManager.shared.addTrackToPlaylist(trackId: trackId, playlistId: playlistId)
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "'\(track.title)' was added to '\(playlist.name)'")
                }
            } catch DatabaseError.duplicateTrackInPlaylist {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.warning, "'\(track.title)' is already in '\(playlist.name)'")
                }
            } catch {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to add track to playlist")
                }
            }
        }
    }
    
    static func removeFromPlaylist(_ track: Track, playlistItem: PlaylistItem, onRemove: @escaping () -> Void) {
        guard case .user(let playlist) = playlistItem.type,
              let playlistId = playlist.id,
              let trackId = track.trackId else { return }
        
        Task {
            do {
                try await DatabaseManager.shared.removeTrackFromPlaylist(trackId: trackId, playlistId: playlistId)
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "'\(track.title)' was removed from '\(playlistItem.name)'")
                    onRemove()
                }
            } catch {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to remove track from playlist")
                }
            }
        }
    }
    
    // MARK: - File Actions
    
    static func showInFinder(_ track: Track) {
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }
    
    static func showTrackInfo(_ track: Track) {
        // Post notification to show track info
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowTrackInfo"),
            object: track
        )
    }
    
    // MARK: - Favorite Actions
    
    static func toggleFavorite(_ track: Track) {
        var updatedTrack = track
        updatedTrack.isFavorite.toggle()
        
        Task {
            do {
                try await DatabaseManager.shared.updateTrackFavoriteStatus(updatedTrack)
            } catch {
                Logger.error("Failed to update favorite: \(error)")
            }
        }
    }
    
    // MARK: - Playlists Helper
    
    static func getUserPlaylists() -> [Playlist] {
        DatabaseCache.shared.allPlaylists.filter { !$0.isSmart }
    }
    
    // MARK: - R128 Scanning Actions
    
    static func scanTrackR128(_ track: Track) {
        R128LoudnessScanner.shared.scanTracks([track])
        NotificationManager.shared.addMessage(.info, "Scanning '\(track.title)' for R128 loudness...")
    }
    
    static func scanAlbumR128(_ track: Track) {
        R128LoudnessScanner.shared.scanAlbum(album: track.album, artist: track.artist)
        NotificationManager.shared.addMessage(.info, "Scanning album '\(track.album)' for R128 loudness...")
    }
    
    static func scanArtistR128(_ track: Track) {
        R128LoudnessScanner.shared.scanArtist(artist: track.artist)
        NotificationManager.shared.addMessage(.info, "Scanning tracks by '\(track.artist)' for R128 loudness...")
    }
    
    // MARK: - Navigation Actions
    
    static func navigateToAlbum(_ track: Track) {
        Task {
            do {
                // Fetch the album from the database
                if let albumId = try await DatabaseManager.shared.getAlbumId(title: track.album, artist: track.artist) {
                    let album = try await DatabaseManager.shared.getAlbum(albumId: albumId)
                    
                    await MainActor.run {
                        // Navigate to the album
                        NotificationCenter.default.post(
                            name: .navigateToEntity,
                            object: EntityType.album(album)
                        )
                    }
                } else {
                    await MainActor.run {
                        NotificationManager.shared.addMessage(.warning, "Album '\(track.album)' not found")
                    }
                }
            } catch {
                Logger.error("Failed to navigate to album: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to navigate to album")
                }
            }
        }
    }
    
    static func navigateToArtist(_ track: Track) {
        Task {
            do {
                // Fetch the artist from the database
                if let artistId = try await DatabaseManager.shared.getArtistId(name: track.artist) {
                    let artist = try await DatabaseManager.shared.getArtist(artistId: artistId)
                    
                    await MainActor.run {
                        // Navigate to the artist
                        NotificationCenter.default.post(
                            name: .navigateToEntity,
                            object: EntityType.artist(artist)
                        )
                    }
                } else {
                    await MainActor.run {
                        NotificationManager.shared.addMessage(.warning, "Artist '\(track.artist)' not found")
                    }
                }
            } catch {
                Logger.error("Failed to navigate to artist: \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to navigate to artist")
                }
            }
        }
    }
}
