//
//  BASSAudioEngine.swift
//  HiFidelity
//
//  Created by Varun Rathod on 14/11/25.
//

import Foundation
import Bass        // Core BASS audio library


/// BASS audio engine for high-quality audio playback
/// Uses BASS library from un4seen.com via CBass Swift wrapper
class BASSAudioEngine {
    // MARK: - Properties
    
    private var currentStream: HSTREAM = 0
    private var nextStream: HSTREAM = 0  // For gapless playback
    private var isInitialized = false
    private var loadedPlugins: [HPLUGIN] = []
    private let settings = AudioSettings.shared
    private let effectsManager = AudioEffectsManager.shared
    
    weak var delegate: BASSAudioEngineDelegate?
    
    // MARK: - Initialization
    
    init() {
        initializeBASSEngine()
        observeSettingsChanges()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Engine Setup
    
    private func initializeBASSEngine() {
        // Initialize BASS audio device with user settings
        let sampleRate = DWORD(settings.sampleRate)
        let flags: DWORD = 0
        
        let result = BASS_Init(-1, sampleRate, flags, nil, nil)
        
        if result == 0 {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("BASS initialization failed with error: \(errorCode)")
            isInitialized = false
        } else {
            Logger.info("BASS audio engine initialized successfully")
            Logger.info("Sample rate: \(settings.sampleRate) Hz, Buffer: \(settings.bufferLength) ms")
            isInitialized = true
            
            // Apply user configuration
            applyAudioSettings()
            
            // Load plugins for extended format support
            loadPlugins()
        }
    }
    
    /// Apply global audio settings from AudioSettings
    /// These settings affect the BASS engine globally
    private func applyAudioSettings() {
        // BASS_CONFIG_BUFFER - Playback buffer length in milliseconds
        BASS_SetConfig(DWORD(BASS_CONFIG_BUFFER), DWORD(settings.bufferLength))
        
        // BASS_CONFIG_SRC - Sample rate conversion quality
        // 0=linear, 1=8-point sinc, 2=16-point sinc, 3=32-point sinc
        BASS_SetConfig(DWORD(BASS_CONFIG_SRC), DWORD(settings.resamplingQuality.bassValue))
        
        // BASS_CONFIG_FLOATDSP - Always use floating-point for best quality
        BASS_SetConfig(DWORD(BASS_CONFIG_FLOATDSP), 1)
        
        
        Logger.debug("Applied audio settings: buffer=\(settings.bufferLength)ms, quality=\(settings.resamplingQuality.description)")
    }
    
    /// Apply per-channel settings using BASS_ChannelSetAttribute
    /// These can be changed at runtime without restart
    private func applyChannelSettings() {
        guard currentStream != 0 else { return }
        
        // Set volume (BASS_ATTRIB_VOL: 0.0 to 1.0)
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), Float(settings.playbackVolume))
        
        Logger.debug("Applied channel settings: volume=\(settings.playbackVolume)")
    }
    
    /// Observe settings changes and reapply
    private func observeSettingsChanges() {
        // Global settings changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAudioSettings()
            self?.applyChannelSettings()
        }
    }
    
    /// Load BASS plugins from the Frameworks folder
    private func loadPlugins() {
        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            Logger.warning("Could not find Frameworks path")
            return
        }
        
        // Only load decoder plugins (exclude core library, effects, and encoding)
        let decoderPlugins = [
            "libbassflac.dylib",    // FLAC decoder
            "libbassopus.dylib",    // Opus decoder
            "libbasswebm.dylib",    // WebM/VP8/VP9 decoder
            "libbasswv.dylib",      // WavPack decoder
            "libbassape.dylib",     // APE (Monkey's Audio) decoder
            "libbassdsd.dylib",     // DSD audio decoder
            "libbassmidi.dylib",    // MIDI file decoder
            "libbass_mpc.dylib",    // Musepack decoder
            "libbass_spx.dylib",    // Speex decoder
            "libbass_tta.dylib",    // TTA (True Audio) decoder
            "libbasshls.dylib"      // HLS streaming support
        ]
        
        Logger.debug("Loading BASS decoder plugins from: \(frameworksPath)")
        
        var loadedCount = 0
        var notFoundPlugins: [String] = []
        
        for pluginFile in decoderPlugins {
            let pluginPath = "\(frameworksPath)/\(pluginFile)"
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: pluginPath) else {
                notFoundPlugins.append(pluginFile)
                continue
            }
            
            // Try to load the plugin
            let plugin = BASS_PluginLoad(pluginPath, 0)
            
            if plugin != 0 {
                loadedPlugins.append(plugin)
                loadedCount += 1
                Logger.info("Loaded: \(pluginFile)")
            } else {
                let errorCode = BASS_ErrorGetCode()
                Logger.warning("Failed to load \(pluginFile): error \(errorCode)")
            }
        }
        
        // Log summary
        Logger.info("Loaded \(loadedCount)/\(decoderPlugins.count) decoder plugins")
        
        if !notFoundPlugins.isEmpty {
            Logger.debug("Plugins not found: \(notFoundPlugins.joined(separator: ", "))")
        }
        
        // Log core format support
        Logger.info("Core formats: MP3, MP2, MP1, OGG, WAV, AIFF")
    }
    
    // MARK: - Playback Control
    
    func load(url: URL) -> Bool {
        guard isInitialized else {
            Logger.error("BASS engine not initialized")
            return false
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.error("File does not exist: \(url.path)")
            return false
        }
        
        // Stop current stream if any
        stop()
        
        // Create stream from file
        // BASS will automatically detect format and use appropriate plugin
        let path = url.path
        
        
        
        currentStream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            path,
            0,
            0,
            DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN) // 32-bit floating-point for best quality
        )
        
        if currentStream == 0 {
            let errorCode = BASS_ErrorGetCode()
            let errorDescription = getLastError()
            Logger.error("Failed to create BASS stream for '\(url.lastPathComponent)'")
            Logger.error("  Path: \(url.path)")
            Logger.error("  Error code: \(errorCode) - \(errorDescription)")
            Logger.error("  File extension: \(url.pathExtension)")
            
            return false
        }
        
        Logger.info("Loaded track: \(url.lastPathComponent)")
        
        // Apply channel-specific settings (volume, etc.)
//        applyChannelSettings()
        
        // Set up end-of-stream callback
        setupStreamEndCallback()
        
        // Apply audio effects to the new stream
        effectsManager.setStream(currentStream)
        
        return true
    }
    
    func play() -> Bool {
        guard currentStream != 0 else {
            Logger.error("No stream loaded")
            return false
        }
        
        let result = BASS_ChannelPlay(currentStream, 0) // 0 = don't restart from beginning
        
        if result == 0 {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to play stream, error: \(errorCode)")
            return false
        }
        
        Logger.debug("Playing stream")
        return true
    }
    
    func pause() -> Bool {
        guard currentStream != 0 else { return false }
        
        let result = BASS_ChannelPause(currentStream)
        
        Logger.debug("Paused stream")
        return result != 0
    }
    
    func stop() {
        guard currentStream != 0 else { return }
        
        // Clear effects before freeing stream
        effectsManager.clearStream()
        
        BASS_ChannelStop(currentStream)
        BASS_StreamFree(currentStream)
        currentStream = 0
        
        Logger.debug("Stopped stream")
    }
    
    func resume() -> Bool {
        return play()
    }
    
    // MARK: - Gapless Playback
    
    /// Pre-load the next track for gapless playback
    func preloadNext(url: URL) -> Bool {
        guard isInitialized else {
            Logger.error("BASS engine not initialized")
            return false
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.error("File does not exist: \(url.path)")
            return false
        }
        
        // Free existing next stream if any
        if nextStream != 0 {
            BASS_StreamFree(nextStream)
            nextStream = 0
        }
        
        // Create stream from file for immediate playback after current track ends
        let path = url.path
        
        nextStream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            path,
            0,
            0,
            DWORD(BASS_SAMPLE_FLOAT | BASS_STREAM_PRESCAN)
        )
        
        if nextStream == 0 {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to pre-load next stream: error \(errorCode)")
            return false
        }
        
        Logger.debug("Pre-loaded next track for gapless: \(url.lastPathComponent)")
        return true
    }
    
    /// Switch to the pre-loaded next track (gapless transition)
    func switchToPreloadedTrack(volume: Float) -> Bool {
        guard nextStream != 0 else {
            Logger.error("No pre-loaded track available")
            return false
        }
        
        // Stop and free current stream
        if currentStream != 0 {
            BASS_ChannelStop(currentStream)
            BASS_StreamFree(currentStream)
        }
        
        // Make next stream the current stream
        currentStream = nextStream
        nextStream = 0
        
        // Set up the new stream
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), volume)
        setupStreamEndCallback()
        effectsManager.setStream(currentStream)
        
        // Start playback immediately
        let result = BASS_ChannelPlay(currentStream, 0)
        
        if result == 0 {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to play pre-loaded stream: error \(errorCode)")
            return false
        }
        
        Logger.debug("Switched to pre-loaded track (gapless)")
        return true
    }
    
    /// Check if next track is pre-loaded
    func hasPreloadedTrack() -> Bool {
        return nextStream != 0
    }
    
    /// Clear pre-loaded track
    func clearPreloadedTrack() {
        if nextStream != 0 {
            BASS_StreamFree(nextStream)
            nextStream = 0
            Logger.debug("Cleared pre-loaded track")
        }
    }
    
    // MARK: - Stream Properties
    
    func getDuration() -> Double {
        guard currentStream != 0 else { return 0 }
        
        let lengthInBytes = BASS_ChannelGetLength(currentStream, DWORD(BASS_POS_BYTE))
        guard lengthInBytes != QWORD(bitPattern: -1) else { return 0 }
        
        let lengthInSeconds = BASS_ChannelBytes2Seconds(currentStream, lengthInBytes)
        return lengthInSeconds
    }
    
    func getCurrentTime() -> Double {
        guard currentStream != 0 else { return 0 }
        
        let positionInBytes = BASS_ChannelGetPosition(currentStream, DWORD(BASS_POS_BYTE))
        guard positionInBytes != QWORD(bitPattern: -1) else { return 0 }
        
        let positionInSeconds = BASS_ChannelBytes2Seconds(currentStream, positionInBytes)
        return positionInSeconds
    }
    
    func seek(to timeInSeconds: Double) -> Bool {
        guard currentStream != 0 else { return false }
        
        let positionInBytes = BASS_ChannelSeconds2Bytes(currentStream, timeInSeconds)
        let result = BASS_ChannelSetPosition(currentStream, positionInBytes, DWORD(BASS_POS_BYTE))
        
        if result != 0 {
            Logger.debug("Seeked to \(timeInSeconds) seconds")
        }
        
        return result != 0
    }
    
    func setVolume(_ volume: Float) {
        guard currentStream != 0 else { return }
        
        // BASS volume is 0-1
        let clampedVolume = max(0.0, min(1.0, volume))
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), clampedVolume)
        
        Logger.debug("Set volume to \(clampedVolume)")
    }
    
    func isPlaying() -> Bool {
        guard currentStream != 0 else { return false }
        
        let state = BASS_ChannelIsActive(currentStream)
        return state == DWORD(BASS_ACTIVE_PLAYING)
    }
    
    // MARK: - Stream End Callback
    
    private func setupStreamEndCallback() {
        // Set up callback for when stream ends
        BASS_ChannelSetSync(
            currentStream,
            DWORD(BASS_SYNC_END),
            0,
            { handle, channel, data, user in
                // Notify delegate that stream ended
                NotificationCenter.default.post(name: .bassStreamEnded, object: nil)
            },
            nil
        )
    }
    
    // MARK: - Audio Information
    
    func getStreamInfo() -> BASSStreamInfo? {
        guard currentStream != 0 else { return nil }
        
        var info = BASS_CHANNELINFO()
        let result = BASS_ChannelGetInfo(currentStream, &info)
        
        guard result != 0 else { return nil }
        
        return BASSStreamInfo(
            frequency: Int(info.freq),
            channels: Int(info.chans),
            bitrate: Int(BASS_StreamGetFilePosition(currentStream, DWORD(BASS_FILEPOS_END)))
        )
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stop()
        
        if isInitialized {
            // Unload all plugins
            for plugin in loadedPlugins {
                BASS_PluginFree(plugin)
            }
            loadedPlugins.removeAll()
            Logger.debug("Unloaded \(loadedPlugins.count) plugin(s)")
            
            BASS_Free()
            isInitialized = false
            Logger.info("BASS audio engine cleaned up")
        }
    }
    
    // MARK: - Error Handling
    
    func getLastError() -> String {
        let errorCode = BASS_ErrorGetCode()
        return BASSError(rawValue: Int(errorCode))?.description ?? "Unknown error (\(errorCode))"
    }
}

// MARK: - Delegate Protocol

protocol BASSAudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: BASSAudioEngine, didUpdateTime time: Double)
    func audioEngineDidFinishPlaying(_ engine: BASSAudioEngine)
}

// MARK: - Stream Info

struct BASSStreamInfo {
    let frequency: Int
    let channels: Int
    let bitrate: Int
}

// MARK: - BASS Error Codes

enum BASSError: Int {
    case ok = 0
    case mem = 1
    case fileOpen = 2
    case driver = 3
    case bufLost = 4
    case handle = 5
    case format = 6
    case position = 7
    case initialization = 8
    case start = 9
    case already = 14
    case notAvail = 18
    case decode = 19
    case dx = 20
    case timeout = 21
    case fileForm = 23
    case speaker = 24
    case version = 25
    case codec = 26
    case ended = 27
    case busy = 28
    case unknown = -1
    
    var description: String {
        switch self {
        case .ok: return "All is OK"
        case .mem: return "Memory error"
        case .fileOpen: return "Cannot open the file"
        case .driver: return "Cannot find a free/valid driver"
        case .bufLost: return "Sample buffer was lost"
        case .handle: return "Invalid handle"
        case .format: return "Unsupported sample format"
        case .position: return "Invalid position"
        case .initialization: return "BASS_Init has not been successfully called"
        case .start: return "BASS_Start has not been successfully called"
        case .already: return "Already initialized/started"
        case .notAvail: return "Not available"
        case .decode: return "Channel is not a 'decoding channel'"
        case .dx: return "DirectX not available"
        case .timeout: return "Timeout"
        case .fileForm: return "Unsupported file format"
        case .speaker: return "Invalid speaker config"
        case .version: return "Invalid BASS version"
        case .codec: return "Codec not available"
        case .ended: return "Stream has ended"
        case .busy: return "Device is busy"
        case .unknown: return "Unknown error"
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let bassStreamEnded = Notification.Name("BASSStreamEnded")
}

