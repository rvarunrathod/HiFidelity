//
//  TrackContextMenu.swift
//  HiFidelity
//
//  Context menu for track operations
//

import SwiftUI
import AppKit

// MARK: - Track Context Menu

struct TrackContextMenu: View {
    let track: Track
    
    // Optional playlist context - if provided, shows "Remove from Playlist" option
    var playlistContext: PlaylistContext?
    
    @ObservedObject private var cache = DatabaseCache.shared
    @ObservedObject private var replayGainSettings = ReplayGainSettings.shared
    
    // Filter to only show user playlists (exclude smart playlists)
    private var userPlaylists: [Playlist] {
        TrackContextMenuBuilder.getUserPlaylists()
    }
    
    // MARK: - Playlist Context
    
    struct PlaylistContext {
        let playlist: PlaylistItem
        let onRemove: () -> Void
    }
    
    var body: some View {
        Group {
            // Playback actions
            Button("Play") {
                TrackContextMenuBuilder.playTrack(track)
            }
            
            Button("Play Next") {
                TrackContextMenuBuilder.playNext(track)
            }
            
            Button("Add to Queue") {
                TrackContextMenuBuilder.addToQueue(track)
            }
            
            Divider()
            
            // Playlist actions
            Menu("Add to Playlist") {
                Button("New Playlist...") {
                    TrackContextMenuBuilder.showCreatePlaylist(with: track)
                }
                
                if !userPlaylists.isEmpty {
                    Divider()
                    
                    ForEach(userPlaylists) { playlist in
                        Button(playlist.name) {
                            TrackContextMenuBuilder.addToPlaylist(track, playlist: playlist)
                        }
                    }
                } else {
                    Divider()
                    
                    Text("No playlists")
                        .foregroundColor(.secondary)
                }
            }
            
            // Remove from playlist (only shown in playlist context)
            if let context = playlistContext, !context.playlist.isSmart {
                Button("Remove from Playlist") {
                    TrackContextMenuBuilder.removeFromPlaylist(track, playlistItem: context.playlist, onRemove: context.onRemove)
                }
            }
            
            Divider()
            
            // File system actions
            Button("Show in Finder") {
                TrackContextMenuBuilder.showInFinder(track)
            }
            
            Button("Get Info") {
                TrackContextMenuBuilder.showTrackInfo(track)
            }
            
            Divider()
            
            // R128 Scanning (only if enabled)
            if ReplayGainSettings.shared.isEnabled {
                Menu("Scan R128 Loudness") {
                    Button("This Track") {
                        TrackContextMenuBuilder.scanTrackR128(track)
                    }
                    
                    Button("Album '\(track.album)'") {
                        TrackContextMenuBuilder.scanAlbumR128(track)
                    }
                    
                    Button("Artist '\(track.artist)'") {
                        TrackContextMenuBuilder.scanArtistR128(track)
                    }
                }
                
                Divider()
            }
            
            // Favorite toggle
            Button(track.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                TrackContextMenuBuilder.toggleFavorite(track)
            }
        }
    }
}

// MARK: - Create Playlist With Track View

struct CreatePlaylistWithTrackView: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        CreatePlaylistView()
            .onReceive(NotificationCenter.default.publisher(for: .playlistCreated)) { notification in
                // Auto-add track to newly created playlist
                if let playlist = notification.object as? Playlist,
                   let playlistId = playlist.id,
                   let trackId = track.trackId {
                    Task {
                        try? await DatabaseManager.shared.addTrackToPlaylist(trackId: trackId, playlistId: playlistId)
                    }
                }
                dismiss()
            }
    }
}

