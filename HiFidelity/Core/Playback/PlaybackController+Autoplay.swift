//
//  PlaybackController+Autoplay.swift
//  HiFidelity
//
//  Autoplay and recommendation logic
//

import Foundation

extension PlaybackController {
    // MARK: - Autoplay Logic
    
    /// Check if autoplay should be triggered (20 seconds or less remaining and approaching queue end)
    func checkAutoplayTrigger() {
        guard isAutoplayEnabled, !hasTriggeredAutoplay else { return }
        
        // Check if we're near the end of the current track (20 seconds or less)
        let timeRemaining = duration - currentTime
        guard timeRemaining > 0 && timeRemaining <= 20 else { return }
        
        // Check if we're at or near the end of the queue
        let isLastTrack = currentQueueIndex >= queue.count - 1
        let isSecondToLast = currentQueueIndex == queue.count - 2
        
        guard isLastTrack || isSecondToLast else { return }
        
        // Trigger autoplay
        hasTriggeredAutoplay = true
        Logger.info("Autoplay triggered: \(timeRemaining)s remaining, queue ending soon")
        
        Task {
            await addAutoplayRecommendations()
        }
    }
    
    /// Add recommended tracks to the queue for autoplay
    func addAutoplayRecommendations() async {
        do {
            // Get recent tracks from queue for context
            let recentTracks = Array(queue.suffix(min(5, queue.count)))
            
            // Get recommendations
            let recommendations = try await recommendationEngine.getAutoplayRecommendations(
                basedOnRecent: recentTracks,
                count: 5
            )
            
            guard !recommendations.isEmpty else {
                Logger.warning("No recommendations available for autoplay")
                return
            }
            
            // Add to queue
            await MainActor.run {
                queue.append(contentsOf: recommendations)
                Logger.info("Added \(recommendations.count) autoplay recommendations to queue")
                
                // Notify user
                NotificationManager.shared.addMessage(.info, "Added \(recommendations.count) recommended tracks to queue")
            }
        } catch {
            Logger.error("Failed to get autoplay recommendations: \(error)")
        }
    }
    
    /// Handle autoplay when queue is completely empty
    func handleEmptyQueue() async {
        Logger.info("Queue empty, attempting autoplay")
        
        // Use play history for recommendations
        let recentTracks = Array(playbackHistory.suffix(5))
        
        do {
            let recommendations = try await recommendationEngine.getAutoplayRecommendations(
                basedOnRecent: recentTracks,
                count: 10
            )
            
            guard !recommendations.isEmpty else {
                // No recommendations available - stop playback
                await MainActor.run {
                    stopPlayback()
                }
                return
            }
            
            await MainActor.run {
                playTracks(recommendations)
            }
        } catch {
            Logger.error("Failed to get recommendations for empty queue: \(error)")
            // Failed to get recommendations - stop playback
            await MainActor.run {
                stopPlayback()
            }
        }
    }
    
    /// Handle autoplay when queue ends
    func handleQueueEnd() async {
        Logger.info("Queue ended, attempting autoplay")
        
        do {
            let recentTracks = Array(queue.suffix(5))
            let recommendations = try await recommendationEngine.getAutoplayRecommendations(
                basedOnRecent: recentTracks,
                count: 10
            )
            
            guard !recommendations.isEmpty else {
                // No recommendations available - stop playback
                await MainActor.run {
                    stopPlayback()
                }
                return
            }
            
            await MainActor.run {
                queue.append(contentsOf: recommendations)
                // Continue playing
                if currentQueueIndex < queue.count - 1 {
                    currentQueueIndex += 1
                    playTrackAtIndex(currentQueueIndex)
                }
            }
        } catch {
            Logger.error("Failed to get recommendations for queue end: \(error)")
            // Failed to get recommendations - stop playback
            await MainActor.run {
                stopPlayback()
            }
        }
    }
}

