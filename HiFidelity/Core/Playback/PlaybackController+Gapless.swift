//
//  PlaybackController+Gapless.swift
//  HiFidelity
//
//  Gapless playback logic
//

import Foundation

extension PlaybackController {
    // MARK: - Gapless Playback
    
    /// Check if we should pre-load the next track for gapless playback
    func checkGaplessPreload() {
        guard !isNextTrackPreloaded, nextTrack != nil else { return }
        
        let timeRemaining = duration - currentTime
        
        // Pre-load when we're within threshold seconds of the end
        guard timeRemaining > 0 && timeRemaining <= gaplessThreshold else { return }
        
        Logger.debug("Gapless pre-load triggered: \(timeRemaining)s remaining")
        preloadNextTrack()
    }
    
    /// Prepare the next track for gapless playback
    func prepareNextTrackForGapless() {
        // Determine what the next track will be
        let nextIndex = getNextTrackIndex()
        
        guard let index = nextIndex, index >= 0 && index < queue.count else {
            // No next track available
            nextTrack = nil
            isNextTrackPreloaded = false
            return
        }
        
        nextTrack = queue[index]
        Logger.debug("Identified next track for gapless: \(nextTrack?.title ?? "unknown")")
    }
    
    /// Get the index of the next track that will play
    func getNextTrackIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        
        if isShuffleEnabled {
            // Find next unplayed track in shuffle mode
            return findNextUnplayedShuffleIndex()
        } else {
            // Regular mode
            if currentQueueIndex < queue.count - 1 {
                return currentQueueIndex + 1
            } else if repeatMode == .all {
                return 0
            } else {
                return nil
            }
        }
    }
    
    /// Pre-load the next track when approaching the end of current track
    func preloadNextTrack() {
        guard let track = nextTrack, !isNextTrackPreloaded else { return }
        
        Logger.info("Pre-loading next track for gapless: \(track.title)")
        
        // Pre-load using BASS engine's dual-stream capability
        let success = audioEngine.preloadNext(url: track.url)
        
        if success {
            isNextTrackPreloaded = true
            Logger.debug("Next track pre-loaded successfully")
        } else {
            Logger.warning("Failed to pre-load next track")
            isNextTrackPreloaded = false
        }
    }
    
    /// Play the pre-loaded next track (gapless transition)
    func playPreloadedTrack() {
        Logger.info("Playing pre-loaded track for gapless playback")
        
        guard let track = nextTrack, isNextTrackPreloaded else {
            Logger.warning("No pre-loaded track available, falling back to regular next")
            next()
            return
        }
        
        // Update queue position
        if isShuffleEnabled {
            // Mark current as played in shuffle mode
            if currentQueueIndex >= 0 && currentQueueIndex < shuffledIndices.count {
                shufflePlayedIndices.insert(shuffledIndices[currentQueueIndex])
            }
            
            // Find next unplayed or move to next position
            if let nextIndex = findNextUnplayedShuffleIndex() {
                currentQueueIndex = nextIndex
            } else if repeatMode == .all {
                resetShuffleState()
                currentQueueIndex = 0
            } else {
                currentQueueIndex += 1
            }
        } else {
            currentQueueIndex += 1
        }
        
        // Save previous track to history
        if let previous = currentTrack {
            playbackHistory.append(previous)
        }
        
        // Update current track
        currentTrack = track
        currentTime = 0
        
        // Switch to pre-loaded stream (gapless)
        let success = audioEngine.switchToPreloadedTrack(volume: Float(isMuted ? 0 : volume))
        
        if !success {
            Logger.warning("Gapless switch failed, falling back to normal load")
            // Fallback: load and play normally
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to load track: \(track.title)")
                return
            }
            audioEngine.setVolume(Float(isMuted ? 0 : volume))
            _ = audioEngine.play()
        }
        
        duration = audioEngine.getDuration()
        isPlaying = true
        startPositionTimer()
        
        // Reset gapless state and prepare next track
        isNextTrackPreloaded = false
        nextTrack = nil
        prepareNextTrackForGapless()
        
        // Update play count
        updatePlayCount(for: track)
        
        Logger.info("Gapless transition complete: \(track.title)")
    }
}

