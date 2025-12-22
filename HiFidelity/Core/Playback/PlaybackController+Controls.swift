//
//  PlaybackController+Controls.swift
//  HiFidelity
//
//  Playback control methods (play, pause, stop, seek)
//

import Foundation

extension PlaybackController {
    // MARK: - Playback Controls
    
    func play() {
        guard let track = currentTrack else { return }
        
        // If track has ended (currentTime >= duration), restart from beginning
        if currentTime >= duration && duration > 0 {
            currentTime = 0
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to reload track: \(track.title)")
                return
            }
            duration = audioEngine.getDuration()
            
            // Apply replay gain and set volume
            applyReplayGain()
            
            // Update stream info immediately
            currentStreamInfo = audioEngine.getStreamInfo()
        }
        // Load track if not already loaded
        else if !audioEngine.isPlaying() && currentTime == 0 {
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to load track: \(track.title)")
                return
            }
            
            duration = audioEngine.getDuration()
            
            // Apply replay gain and set volume
            applyReplayGain()
            
            // Update stream info immediately
            currentStreamInfo = audioEngine.getStreamInfo()
        }
        
        // Play
        guard audioEngine.play() else {
            Logger.error("Failed to play track: \(track.title)")
            return
        }
        
        isPlaying = true
        startPositionTimer()
        Logger.info("Playing: \(track.title)")
        
        // Update play count
        updatePlayCount(for: track)
    }
    
    func pause() {
        guard audioEngine.pause() else { return }
        
        isPlaying = false
        stopPositionTimer()
        Logger.info("Paused")
    }
    
    func stop() {
        audioEngine.stop()
        isPlaying = false
        stopPositionTimer()
        Logger.info("Stopped")
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    /// Stop playback when queue ends (pause instead of stop to keep track loaded for seeking)
    func stopPlayback() {
        _ = audioEngine.pause()
        audioEngine.clearPreloadedTrack()
        isPlaying = false
        stopPositionTimer()
        
        // Clear gapless state
        nextTrack = nil
        isNextTrackPreloaded = false
        
        Logger.info("Playback stopped - end of queue")
    }
    
    // MARK: - Seeking
    
    func seek(to time: Double) {
        // If track is not loaded or seek fails, try to reload and seek
        if !audioEngine.seek(to: time) {
            // Try to reload the track if we have one
            guard let track = currentTrack else {
                Logger.error("Failed to seek to \(time) - no track loaded")
                return
            }
            
            Logger.info("Track not loaded, reloading for seek...")
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to reload track for seeking")
                return
            }
            
            duration = audioEngine.getDuration()
            
            // Apply replay gain and set volume
            applyReplayGain()
            
            // Try seeking again
            guard audioEngine.seek(to: time) else {
                Logger.error("Failed to seek to \(time) after reload")
                return
            }
        }
        
        currentTime = time
        Logger.info("Seeked to: \(time)")
    }
    
    func seekForward(_ seconds: Double = 10) {
        let newTime = min(currentTime + seconds, duration - 1)
        seek(to: newTime)
    }
    
    func seekBackward(_ seconds: Double = 10) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
    func next() {
        guard !queue.isEmpty else {
            // Queue is empty, try autoplay if enabled
            if isAutoplayEnabled {
                Task {
                    await handleEmptyQueue()
                }
            } else {
                // No queue and no autoplay - stop playback
                stopPlayback()
            }
            return
        }
        
        if isShuffleEnabled {
            playNextShuffled()
        } else if currentQueueIndex < queue.count - 1 {
            currentQueueIndex += 1
            playTrackAtIndex(currentQueueIndex)
        } else if repeatMode == .all {
            currentQueueIndex = 0
            playTrackAtIndex(currentQueueIndex)
        } else if repeatMode == .off && isAutoplayEnabled {
            // Reached end of queue with no repeat, try autoplay
            Task {
                await handleQueueEnd()
            }
        } else {
            // Reached end of queue with no repeat and no autoplay - stop playback
            stopPlayback()
        }
    }
    
    func previous() {
        guard !queue.isEmpty else { return }
        
        // If more than 3 seconds have passed, restart current track
        if currentTime > 3.0 {
            seek(to: 0)
        } else if currentQueueIndex > 0 {
            currentQueueIndex -= 1
            playTrackAtIndex(currentQueueIndex)
        }
    }
}

