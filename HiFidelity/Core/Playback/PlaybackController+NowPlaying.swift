//
//  PlaybackController+NowPlaying.swift
//  HiFidelity
//
//  Now Playing Info management for Control Center and Lock Screen
//

import Foundation
import MediaPlayer

extension PlaybackController {
    // MARK: - Now Playing Info
    
    func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        
        // Track metadata
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        
        if let albumArtist = track.albumArtist {
            nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = albumArtist
        }
        
        if let composer = track.composer as String?, !composer.isEmpty && composer != "Unknown Composer" {
            nowPlayingInfo[MPMediaItemPropertyComposer] = composer
        }
        
        if let genre = track.genre as String?, !genre.isEmpty && genre != "Unknown Genre" {
            nowPlayingInfo[MPMediaItemPropertyGenre] = genre
        }
        
        // Track number
        if let trackNumber = track.trackNumber {
            nowPlayingInfo[MPMediaItemPropertyAlbumTrackNumber] = trackNumber
        }
        
        if let totalTracks = track.totalTracks {
            nowPlayingInfo[MPMediaItemPropertyAlbumTrackCount] = totalTracks
        }
        
        // Disc number
        if let discNumber = track.discNumber {
            nowPlayingInfo[MPMediaItemPropertyDiscNumber] = discNumber
        }
        
        if let totalDiscs = track.totalDiscs {
            nowPlayingInfo[MPMediaItemPropertyDiscCount] = totalDiscs
        }
        
        // Playback info
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        Logger.debug("Updated Now Playing info for: \(track.title)")
        
        // Artwork (load from cache if available) - done async to avoid blocking
        if let trackId = track.trackId {
            ArtworkCache.shared.getArtwork(for: trackId) { image in
                guard let image = image else { return }
                
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                
                // Update Now Playing with artwork
                DispatchQueue.main.async {
                    var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updatedInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                }
            }
        }
    }
    
    func updateNowPlayingPlaybackState() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func updateNowPlayingElapsedTime() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

