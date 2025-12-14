//
//  PlaybackController+Queue.swift
//  HiFidelity
//
//  Queue management methods
//

import Foundation

extension PlaybackController {
    // MARK: - Track Management
    
    func play(track: Track) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            currentQueueIndex = index
            playTrackAtIndex(index)
            
            // Mark as played in shuffle mode
            if isShuffleEnabled && index < shuffledIndices.count {
                shufflePlayedIndices.insert(shuffledIndices[index])
            }
        } else {
            // Add to queue and play
            queue.append(track)
            if isShuffleEnabled && !originalQueue.isEmpty {
                originalQueue.append(track)
            }
            currentQueueIndex = queue.count - 1
            playTrackAtIndex(currentQueueIndex)
        }
    }
    
    func playTracks(_ tracks: [Track], startingAt index: Int = 0) {
        // Store original queue for shuffle/unshuffle
        originalQueue = tracks
        originalQueueIndex = index
        
        if isShuffleEnabled {
            // Create shuffled queue starting from the selected track
            createShuffledQueue(startingFrom: index)
        } else {
            queue = tracks
            currentQueueIndex = index
        }
        
        playTrackAtIndex(currentQueueIndex)
    }
    
    /// Play tracks in shuffled order (like Apple Music shuffle play button)
    func playTracksShuffled(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        
        // Store original queue
        originalQueue = tracks
        originalQueueIndex = 0
        
        // Enable shuffle if not already enabled
        let wasShuffleEnabled = isShuffleEnabled
        isShuffleEnabled = true
        
        // Create shuffled queue starting from first track
        createShuffledQueue(startingFrom: 0)
        
        // Play first track in shuffled queue
        playTrackAtIndex(0)
        
        if !wasShuffleEnabled {
            Logger.info("Shuffle play: enabled shuffle and playing \(tracks.count) tracks")
        }
    }
    
    func playTrackAtIndex(_ index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        // Stop current track and clear pre-loaded track
        audioEngine.stop()
        audioEngine.clearPreloadedTrack()
        
        // Save current track to history
        if let current = currentTrack {
            playbackHistory.append(current)
        }
        
        currentTrack = queue[index]
        currentTime = 0
        duration = 0 // Will be set when track loads
        
        // Reset gapless state
        isNextTrackPreloaded = false
        nextTrack = nil
        
        play()
        
        currentStreamInfo = audioEngine.getStreamInfo()
        
        // Pre-load next track for gapless playback
        prepareNextTrackForGapless()
    }
    
    // MARK: - Queue Operations
    
    func addToQueue(_ track: Track) {
        queue.append(track)
        // Also add to original queue if shuffle is enabled
        if isShuffleEnabled && !originalQueue.isEmpty {
            originalQueue.append(track)
        }
    }
    
    func addToQueue(_ tracks: [Track]) {
        queue.append(contentsOf: tracks)
        // Also add to original queue if shuffle is enabled
        if isShuffleEnabled && !originalQueue.isEmpty {
            originalQueue.append(contentsOf: tracks)
        }
    }
    
    func playNext(_ track: Track) {
        let insertIndex = currentQueueIndex + 1
        if insertIndex < queue.count {
            queue.insert(track, at: insertIndex)
        } else {
            queue.append(track)
        }
        
        // Update original queue if shuffle is enabled
        if isShuffleEnabled && !originalQueue.isEmpty {
            // Find position in original queue and insert there too
            if let currentOriginalIndex = currentQueueIndex >= 0 && currentQueueIndex < shuffledIndices.count 
                ? shuffledIndices[currentQueueIndex] : nil {
                let originalInsertIndex = min(currentOriginalIndex + 1, originalQueue.count)
                originalQueue.insert(track, at: originalInsertIndex)
            } else {
                originalQueue.append(track)
            }
        }
        
        // Update gapless state if next track changed
        prepareNextTrackForGapless()
    }
    
    func removeFromQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        queue.remove(at: index)
        
        // Adjust current index if necessary
        if index < currentQueueIndex {
            currentQueueIndex -= 1
        } else if index == currentQueueIndex {
            // Currently playing track was removed
            if !queue.isEmpty {
                playTrackAtIndex(min(currentQueueIndex, queue.count - 1))
            } else {
                currentTrack = nil
                isPlaying = false
            }
        }
        
        // Update gapless state
        prepareNextTrackForGapless()
    }
    
    func clearQueue() {
        queue.removeAll()
        originalQueue.removeAll()
        currentQueueIndex = -1
        originalQueueIndex = -1
        currentTrack = nil
        isPlaying = false
        shuffledIndices.removeAll()
        shufflePlayedIndices.removeAll()
        
        // Clear gapless state
        nextTrack = nil
        isNextTrackPreloaded = false
        audioEngine.clearPreloadedTrack()
    }
    
    func moveQueueItem(from source: Int, to destination: Int) {
        guard source >= 0 && source < queue.count,
              destination >= 0 && destination < queue.count,
              source != destination else { return }
        
        let item = queue.remove(at: source)
        queue.insert(item, at: destination)
        
        // Update current queue index if necessary
        if source == currentQueueIndex {
            currentQueueIndex = destination
        } else if source < currentQueueIndex && destination >= currentQueueIndex {
            currentQueueIndex -= 1
        } else if source > currentQueueIndex && destination <= currentQueueIndex {
            currentQueueIndex += 1
        }
        
        Logger.info("Moved queue item from \(source) to \(destination)")
        
        // Update gapless state
        prepareNextTrackForGapless()
    }
}

