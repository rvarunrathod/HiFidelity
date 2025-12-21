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
}
