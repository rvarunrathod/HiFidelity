//
//  PlaybackController.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import Foundation
import SwiftUI
import MediaPlayer

/// Manages playback state and controls
class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    
    // MARK: - Published Properties
    
    @Published var currentTrack: Track? {
        didSet {
            applyReplayGain()
            updateNowPlayingInfo()
        }
    }
    @Published var isPlaying: Bool = false {
        didSet {
            updateNowPlayingPlaybackState()
        }
    }
    @Published var currentTime: Double = 0.0 {
        didSet {
            updateNowPlayingElapsedTime()
        }
    }
    @Published var duration: Double = 0.0
    @Published var volume: Double = 0.7 {
        didSet {
            // Sync volume to centralized AudioSettings
            AudioSettings.shared.playbackVolume = volume
            // Apply to audio engine with replay gain
            let effectiveVolume = Float(volume) * currentReplayGainMultiplier
            audioEngine.setVolume(effectiveVolume)
        }
    }
    @Published var isMuted: Bool = false
    @Published var repeatMode: RepeatMode = .off {
        didSet {
            // Clear preloaded next track if switching to repeat one
            // since we won't be playing the next track
            if repeatMode == .one && isNextTrackPreloaded {
                audioEngine.clearPreloadedTrack()
                isNextTrackPreloaded = false
                nextTrack = nil
                Logger.debug("Cleared preloaded track (repeat one activated)")
            }
        }
    }
    @Published var isShuffleEnabled: Bool = false
    
    // Audio quality info
    @Published var currentStreamInfo: BASSStreamInfo?
    
    // Queue management
    @Published var queue: [Track] = []
    @Published var playbackHistory: [Track] = []
    @Published var currentQueueIndex: Int = -1
    
    // UI State
    @Published var showQueue: Bool = false
    @Published var showLyrics: Bool = false
    @Published var showVisualizer: Bool = false
    
    // MARK: - Internal Properties
    
    // Audio Engine
    let audioEngine: BASSAudioEngine
    var positionUpdateTimer: Timer?
    
    // Shuffle state
    var originalQueue: [Track] = []
    var originalQueueIndex: Int = -1
    var shuffledIndices: [Int] = []
    var shufflePlayedIndices: Set<Int> = []
    
    // Gapless playback
    var nextTrack: Track?
    var isNextTrackPreloaded = false
    let gaplessThreshold: Double = 5.0  // Pre-load next track when 5 seconds remaining
    
    // Autoplay
    @Published var isAutoplayEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAutoplayEnabled, forKey: "autoplayEnabled")
            Logger.info("Autoplay \(isAutoplayEnabled ? "enabled" : "disabled")")
        }
    }
    var hasTriggeredAutoplay = false
    
    // Recommendation Engine
    let recommendationEngine = RecommendationEngine.shared
    
    // Replay Gain
    let replayGainSettings = ReplayGainSettings.shared
    var currentReplayGainMultiplier: Float = 1.0
    
    // MARK: - Initialization
    
    private init() {
        audioEngine = BASSAudioEngine()
        
        // Load saved volume from centralized AudioSettings
        volume = AudioSettings.shared.playbackVolume
        
        // Load autoplay preference
        isAutoplayEnabled = UserDefaults.standard.bool(forKey: "autoplayEnabled")
        
        setupNotifications()
        setupRemoteCommandCenter()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStreamEnded),
            name: .bassStreamEnded,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGaplessTransition),
            name: .bassGaplessTransition,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChanged),
            name: .audioDeviceChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceRemoved),
            name: .audioDeviceRemoved,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChangeComplete),
            name: .audioDeviceChangeComplete,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReplayGainSettingsChanged),
            name: NSNotification.Name("ReplayGainSettingsChanged"),
            object: nil
        )
    }
    
    @objc private func handleDeviceChanged(_ notification: Notification) {
        guard let device = notification.object as? AudioOutputDevice else { return }
        
        Logger.info("Audio device changed to: \(device.name)")
        
        // BASSAudioEngine will attempt to move streams to the new device
        // Wait for the completion notification to see if reload is needed
    }
    
    @objc private func handleDeviceChangeComplete(_ notification: Notification) {
        Logger.debug("Device change complete notification received")
        
        guard let userInfo = notification.userInfo,
              let needsReload = userInfo["needsReload"] as? Bool else {
            Logger.warning("Device change complete but no userInfo")
            return
        }
        
        Logger.debug("needsReload: \(needsReload), currentTrack: \(currentTrack?.title ?? "none")")
        
        if needsReload, let track = currentTrack {
            Logger.info("Reloading track on new device: \(track.title)")
            
            // Save playback state
            let wasPlaying = isPlaying
            let savedPosition = currentTime
            
            // Reload the track
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to reload track on new device")
                return
            }
            
            duration = audioEngine.getDuration()
            
            // Apply replay gain and set volume
            applyReplayGain()
            
            // Restore position
            if savedPosition > 0 && savedPosition < duration {
                _ = audioEngine.seek(to: savedPosition)
                currentTime = savedPosition
            }
            
            // Resume playback if it was playing
            if wasPlaying {
                _ = audioEngine.play()
                isPlaying = true
                startPositionTimer()
                Logger.info("✓ Resumed playback on new device at \(savedPosition)s")
            } else {
                Logger.info("✓ Track reloaded on new device - ready to play")
            }
            
            // Update stream info after reload
            currentStreamInfo = audioEngine.getStreamInfo()
        } else if !needsReload {
            Logger.info("Stream successfully moved to new device without reload")
            
            // Update stream info even if not reloaded
            currentStreamInfo = audioEngine.getStreamInfo()
        } else {
            Logger.warning("Device change complete but no track to reload")
        }
    }
    
    @objc private func handleDeviceRemoved(_ notification: Notification) {
        Logger.warning("⚠️ Audio device was removed - pausing playback")
        
        // Pause playback
        if isPlaying {
            pause()
        }
        
        // Clear the audio engine's streams (they reference invalid device)
        audioEngine.stop()
        
        // DACManager will auto-switch to default device and post audioDeviceChanged
        // Since stream is cleared, handleDeviceChangeComplete will reload the track
    }
    
    @objc private func handleReplayGainSettingsChanged() {
        Logger.info("ReplayGain settings changed - recalculating gain")
        
        // Recalculate and apply replay gain for current track
        applyReplayGain()
    }
    
    /// Calculate and apply replay gain for the current track
    func applyReplayGain() {
        guard let track = currentTrack else {
            currentReplayGainMultiplier = 1.0
            return
        }
        
        // Calculate replay gain multiplier
        currentReplayGainMultiplier = replayGainSettings.calculateGainMultiplier(for: track)
        
        // Apply the combined volume (user volume × replay gain)
        let effectiveVolume = Float(isMuted ? 0 : volume) * currentReplayGainMultiplier
        audioEngine.setVolume(effectiveVolume)
        
        Logger.debug("Applied replay gain: user=\(volume), gain=×\(currentReplayGainMultiplier), effective=\(effectiveVolume)")
    }

    
    @objc func handleStreamEnded() {
        Logger.info("Stream ended")
        
        switch repeatMode {
        case .one:
            // Replay current track
            DispatchQueue.main.async {
                self.seek(to: 0)
                self.play()
            }
        case .all, .off:
            // Play next track (gapless if pre-loaded)
            DispatchQueue.main.async {
                if self.isNextTrackPreloaded && self.nextTrack != nil {
                    self.playPreloadedTrack()
                } else {
                    self.next()
                }
            }
        }
    }
    
    @objc func handleGaplessTransition() {
        Logger.info("Gapless transition triggered (repeat mode: \(repeatMode))")
        
        // IMPORTANT: Check repeat mode first
        // If repeat mode is .one, don't do gapless - let the stream end and the 
        // handleStreamEnded callback will handle the repeat
        guard repeatMode != .one else {
            Logger.debug("Repeat one is active - skipping gapless, will repeat current track")
            return
        }
        
        // This is called 50ms before the track ends by the BASS sync callback
        // Execute the gapless switch immediately for seamless transition
        DispatchQueue.main.async {
            if self.isNextTrackPreloaded && self.nextTrack != nil {
                self.playPreloadedTrack()
            } else {
                Logger.warning("Gapless transition triggered but no preloaded track available")
            }
        }
    }
    
    // MARK: - Progress
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    func setProgress(_ value: Double) {
        let newTime = value * duration
        seek(to: newTime)
    }
}

// MARK: - Repeat Mode

enum RepeatMode {
    case off
    case all
    case one
    
    var iconName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Formatted Time Extension

extension PlaybackController {
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    private func formatTime(_ time: Double) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

