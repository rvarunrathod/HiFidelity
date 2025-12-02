//
//  PlaybackController+Timer.swift
//  HiFidelity
//
//  Position update timer management
//

import Foundation

extension PlaybackController {
    // MARK: - Position Timer
    
    func startPositionTimer() {
        stopPositionTimer()
        
        // Reset autoplay trigger
        hasTriggeredAutoplay = false
        
        // Update position every 0.5 seconds (less CPU intensive)
        // UI updates at 60fps will interpolate smoothly
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.currentTime = self.audioEngine.getCurrentTime()
                
                // Check for gapless pre-loading (5 seconds or less remaining)
                self.checkGaplessPreload()
                
                // Check for autoplay trigger (20 seconds or less remaining)
                self.checkAutoplayTrigger()
            }
        }
        
        // Add timer to common run loop mode so it works during scrolling
        if let timer = positionUpdateTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    func stopPositionTimer() {
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
    }
}

