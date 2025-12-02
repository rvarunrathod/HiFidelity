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
    
    // Shuffle state
    private var originalQueue: [Track] = []
    private var originalQueueIndex: Int = -1
    private var shuffledIndices: [Int] = []
    private var shufflePlayedIndices: Set<Int> = []
    
    // Autoplay
    @Published var isAutoplayEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAutoplayEnabled, forKey: "autoplayEnabled")
            Logger.info("Autoplay \(isAutoplayEnabled ? "enabled" : "disabled")")
        }
    }
    private var hasTriggeredAutoplay = false
    
    // UI State
    @Published var showQueue: Bool = false
    @Published var showLyrics: Bool = false
    @Published var showVisualizer: Bool = false
    
    // BASS Audio Engine
    private let audioEngine: BASSAudioEngine
    private var positionUpdateTimer: Timer?
    
    // Recommendation Engine
    private let recommendationEngine = RecommendationEngine.shared
    
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
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        // Seek forward/backward
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.seekForward(event.interval)
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.seekBackward(event.interval)
            return .success
        }
        
        // Change playback position
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
        
        // Like/Dislike (favorite)
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { [weak self] _ in
            guard let self = self, let track = self.currentTrack, !track.isFavorite else { return .commandFailed }
            self.toggleFavorite()
            return .success
        }
        
        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { [weak self] _ in
            guard let self = self, let track = self.currentTrack, track.isFavorite else { return .commandFailed }
            self.toggleFavorite()
            return .success
        }
        
        Logger.info("Remote command center setup complete")
    }
    
    @objc private func handleStreamEnded() {
        Logger.info("Stream ended, playing next track")
        
        switch repeatMode {
        case .one:
            // Replay current track
            seek(to: 0)
            play()
        case .all, .off:
            // Play next track
            DispatchQueue.main.async {
                self.next()
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func play() {
        guard let track = currentTrack else { return }
        
        // Load track if not already loaded
        if !audioEngine.isPlaying() && currentTime == 0 {
            guard audioEngine.load(url: track.url) else {
                Logger.error("Failed to load track: \(track.title)")
                return
            }
            
            duration = audioEngine.getDuration()
            audioEngine.setVolume(Float(isMuted ? 0 : volume))
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
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func next() {
        guard !queue.isEmpty else {
            // Queue is empty, try autoplay if enabled
            if isAutoplayEnabled {
                Task {
                    await handleEmptyQueue()
                }
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
        }
    }
    
    /// Handle autoplay when queue is completely empty
    private func handleEmptyQueue() async {
        Logger.info("Queue empty, attempting autoplay")
        
        // Use play history for recommendations
        let recentTracks = Array(playbackHistory.suffix(5))
        
        do {
            let recommendations = try await recommendationEngine.getAutoplayRecommendations(
                basedOnRecent: recentTracks,
                count: 10
            )
            
            guard !recommendations.isEmpty else { return }
            
            await MainActor.run {
                playTracks(recommendations)
            }
        } catch {
            Logger.error("Failed to get recommendations for empty queue: \(error)")
        }
    }
    
    /// Handle autoplay when queue ends
    private func handleQueueEnd() async {
        Logger.info("Queue ended, attempting autoplay")
        
        do {
            let recentTracks = Array(queue.suffix(5))
            let recommendations = try await recommendationEngine.getAutoplayRecommendations(
                basedOnRecent: recentTracks,
                count: 10
            )
            
            guard !recommendations.isEmpty else { return }
            
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
    
    func seek(to time: Double) {
        guard audioEngine.seek(to: time) else {
            Logger.error("Failed to seek to \(time)")
            return
        }
        
        currentTime = time
        Logger.info("Seeked to: \(time)")
    }
    
    func seekForward(_ seconds: Double = 10) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func seekBackward(_ seconds: Double = 10) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }
    
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
    
    private func playTrackAtIndex(_ index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        // Stop current track
        audioEngine.stop()
        
        // Save current track to history
        if let current = currentTrack {
            playbackHistory.append(current)
        }
        
        currentTrack = queue[index]
        currentTime = 0
        duration = 0 // Will be set when track loads
        play()
    }
    
    /// Play next track in shuffle mode
    private func playNextShuffled() {
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
            }
        }
    }
    
    /// Find the next unplayed track in shuffle mode
    private func findNextUnplayedShuffleIndex() -> Int? {
        for (queueIndex, originalIndex) in shuffledIndices.enumerated() {
            if queueIndex > currentQueueIndex && !shufflePlayedIndices.contains(originalIndex) {
                return queueIndex
            }
        }
        return nil
    }
    
    /// Reset shuffle state for repeat all
    private func resetShuffleState() {
        shufflePlayedIndices.removeAll()
        // Re-shuffle the indices
        if !originalQueue.isEmpty {
            createShuffledQueue(startingFrom: 0)
        }
    }
    
    /// Create a shuffled queue starting from a specific track
    private func createShuffledQueue(startingFrom index: Int) {
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
    
    // MARK: - Queue Management
    
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
    }
    
    // MARK: - Volume Control
    
    func setVolume(_ value: Double) {
        volume = max(0, min(1, value))
        // Volume is applied via didSet observer
    }
    
    func toggleMute() {
        isMuted.toggle()
        // Apply muted or normal volume
        audioEngine.setVolume(Float(isMuted ? 0 : volume))
    }
    
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
    }
    
    // MARK: - Favorites
    
    func toggleFavorite() {
        guard var track = currentTrack else { return }
        
        guard track.trackId != nil else {
            Logger.error("Cannot update favorite - track has no database ID")
            return
        }
        
        track.isFavorite.toggle()
        currentTrack?.isFavorite = track.isFavorite
        // Update in database
        Task {
            do {
                try await DatabaseManager.shared.updateTrackFavoriteStatus(track)
                Logger.info("Updated favorite status for: \(track.title), isFavorite: \(track.isFavorite)")
            } catch {
                Logger.error("Failed to update favorite: \(error)")
            }
        }
    }
    
    // MARK: - Position Timer
    
    private func startPositionTimer() {
        stopPositionTimer()
        
        // Reset autoplay trigger
        hasTriggeredAutoplay = false
        
        // Update position every 0.5 seconds (less CPU intensive)
        // UI updates at 60fps will interpolate smoothly
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.currentTime = self.audioEngine.getCurrentTime()
                
                // Check for autoplay trigger (20 seconds or less remaining)
                self.checkAutoplayTrigger()
            }
        }
        
        // Add timer to common run loop mode so it works during scrolling
        if let timer = positionUpdateTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopPositionTimer() {
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
    }
    
    // MARK: - Autoplay Logic
    
    /// Check if autoplay should be triggered (20 seconds or less remaining and approaching queue end)
    private func checkAutoplayTrigger() {
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
    private func addAutoplayRecommendations() async {
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
    
    // MARK: - Play Count
    
    private func updatePlayCount(for track: Track) {
        Task {
            guard var track = currentTrack else { return }
                    
            guard track.trackId != nil else {
                Logger.error("Cannot update play count - track has no database ID")
                return
            }
            
            track.playCount = track.playCount + 1
            track.lastPlayedDate = Date()
            
            do {
                try await DatabaseManager.shared.updateTrackPlayInfo(track)
                Logger.debug("Updated play count for: \(track.title)")
            } catch {
                Logger.error("Failed to update play count: \(error)")
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
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo() {
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
    
    private func updateNowPlayingPlaybackState() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingElapsedTime() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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

