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
            // Apply to audio engine
            audioEngine.setVolume(Float(volume))
        }
    }
    @Published var isMuted: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffleEnabled: Bool = false
    
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

