//
//  PlaybackController+Favorites.swift
//  HiFidelity
//
//  Favorite track management
//

import Foundation

extension PlaybackController {
    // MARK: - Favorites
    
    func toggleFavorite() {
        guard var track = currentTrack else { return }
        
        guard track.trackId != nil else {
            Logger.error("Cannot update favorite - track has no database ID")
            return
        }
        
        // Toggle the favorite status
        track.isFavorite.toggle()
        currentTrack = track
        // Update in database
        Task {
            do {
                try await DatabaseManager.shared.updateTrackFavoriteStatus(track)
                Logger.info("Updated favorite status for: \(track.title), isFavorite: \(track.isFavorite)")
            } catch {
                Logger.error("Failed to update favorite: \(error)")
            }
        }
    }
    
    // MARK: - Play Count
    
    func updatePlayCount(for track: Track) {
        Task {
            guard var track = currentTrack else { return }
                    
            guard track.trackId != nil else {
                Logger.error("Cannot update play count - track has no database ID")
                return
            }
            
            track.playCount = track.playCount + 1
            track.lastPlayedDate = Date()
            
            do {
                try await DatabaseManager.shared.updateTrackPlayInfo(track)
                Logger.debug("Updated play count for: \(track.title)")
            } catch {
                Logger.error("Failed to update play count: \(error)")
            }
        }
    }
}

