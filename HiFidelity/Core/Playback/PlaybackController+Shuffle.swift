//
//  PlaybackController+Shuffle.swift
//  HiFidelity
//
//  Shuffle and repeat mode logic
//

import Foundation

extension PlaybackController {
    // MARK: - Repeat & Shuffle
    
    func toggleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
        
        if isShuffleEnabled {
            // Enable shuffle mode
            if !queue.isEmpty {
                // Save current queue as original if not already saved
                if originalQueue.isEmpty {
                    originalQueue = queue
                    originalQueueIndex = currentQueueIndex
                }
                
                // Find the index of current track in original queue
                let currentTrackInOriginal: Int
                if currentQueueIndex >= 0 && currentQueueIndex < queue.count {
                    let currentTrackId = queue[currentQueueIndex].id
                    currentTrackInOriginal = originalQueue.firstIndex(where: { $0.id == currentTrackId }) ?? 0
                } else {
                    currentTrackInOriginal = 0
                }
                
                // Create shuffled queue starting from current track
                createShuffledQueue(startingFrom: currentTrackInOriginal)
            }
            
            Logger.info("Shuffle enabled")
        } else {
            // Disable shuffle mode - restore original queue
            if !originalQueue.isEmpty {
                // Find current track in original queue
                let currentTrackId = currentQueueIndex >= 0 && currentQueueIndex < queue.count 
                    ? queue[currentQueueIndex].id 
                    : nil
                
                // Restore original queue
                queue = originalQueue
                
                // Find current track's position in original queue
                if let trackId = currentTrackId,
                   let originalIndex = originalQueue.firstIndex(where: { $0.id == trackId }) {
                    currentQueueIndex = originalIndex
                } else {
                    currentQueueIndex = originalQueueIndex
                }
                
                // Clear shuffle state
                shuffledIndices.removeAll()
                shufflePlayedIndices.removeAll()
            }
            
            Logger.info("Shuffle disabled, restored original queue order")
        }
        
        // Update gapless state for new queue order
        prepareNextTrackForGapless()
    }
    
    // MARK: - Shuffle Helpers
    
    /// Play next track in shuffle mode
    func playNextShuffled() {
        guard !shuffledIndices.isEmpty else {
            // No shuffle data, fallback to regular next
            if currentQueueIndex < queue.count - 1 {
                currentQueueIndex += 1
                playTrackAtIndex(currentQueueIndex)
            } else if repeatMode == .all {
                // Reset shuffle and start over
                resetShuffleState()
                currentQueueIndex = 0
                playTrackAtIndex(currentQueueIndex)
            } else if repeatMode == .off && isAutoplayEnabled {
                Task {
                    await handleQueueEnd()
                }
            } else {
                // Reached end with no repeat and no autoplay - stop playback
                stopPlayback()
            }
            return
        }
        
        // Mark current index as played
        if currentQueueIndex >= 0 && currentQueueIndex < shuffledIndices.count {
            shufflePlayedIndices.insert(shuffledIndices[currentQueueIndex])
        }
        
        // Find next unplayed track
        if let nextUnplayedIndex = findNextUnplayedShuffleIndex() {
            currentQueueIndex = nextUnplayedIndex
            playTrackAtIndex(currentQueueIndex)
        } else {
            // All tracks played
            if repeatMode == .all {
                // Reset and start over
                resetShuffleState()
                currentQueueIndex = 0
                playTrackAtIndex(currentQueueIndex)
            } else if repeatMode == .off && isAutoplayEnabled {
                Task {
                    await handleQueueEnd()
                }
            } else {
                // Reached end with no repeat and no autoplay - stop playback
                stopPlayback()
            }
        }
    }
    
    /// Find the next unplayed track in shuffle mode
    func findNextUnplayedShuffleIndex() -> Int? {
        for (queueIndex, originalIndex) in shuffledIndices.enumerated() {
            if queueIndex > currentQueueIndex && !shufflePlayedIndices.contains(originalIndex) {
                return queueIndex
            }
        }
        return nil
    }
    
    /// Reset shuffle state for repeat all
    func resetShuffleState() {
        shufflePlayedIndices.removeAll()
        // Re-shuffle the indices
        if !originalQueue.isEmpty {
            createShuffledQueue(startingFrom: 0)
        }
    }
    
    /// Create a shuffled queue starting from a specific track
    func createShuffledQueue(startingFrom index: Int) {
        guard index >= 0 && index < originalQueue.count else { return }
        
        // Create array of indices
        var indices = Array(0..<originalQueue.count)
        
        // Remove the starting index
        indices.remove(at: index)
        
        // Shuffle remaining indices
        indices.shuffle()
        
        // Put starting index first
        indices.insert(index, at: 0)
        
        // Store shuffled indices mapping
        shuffledIndices = indices
        shufflePlayedIndices.removeAll()
        
        // Create shuffled queue
        queue = indices.map { originalQueue[$0] }
        currentQueueIndex = 0 // Starting track is now at index 0
        
        Logger.info("Created shuffled queue with \(queue.count) tracks")
    }
}

