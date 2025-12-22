//
//  PlaybackController+Volume.swift
//  HiFidelity
//
//  Volume control methods
//

import Foundation

extension PlaybackController {
    // MARK: - Volume Control
    
    func setVolume(_ value: Double) {
        volume = max(0, min(1, value))
        // Volume is applied via didSet observer
    }
    
    func toggleMute() {
        isMuted.toggle()
        // Apply muted or normal volume with replay gain
        let effectiveVolume = Float(isMuted ? 0 : volume) * currentReplayGainMultiplier
        audioEngine.setVolume(effectiveVolume)
    }
}

