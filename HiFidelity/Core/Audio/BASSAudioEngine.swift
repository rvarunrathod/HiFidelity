//
//  BASSAudioEngine.swift
//  HiFidelity
//
//  Created by Varun Rathod on 14/11/25.
//

import Foundation
import CoreAudio
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
    private let dacManager = DACManager.shared
    
    weak var delegate: BASSAudioEngineDelegate?
    
    // MARK: - Initialization
    
    init() {
        initializeBASSEngine()
        observeSettingsChanges()
    }
    
    deinit {
        cleanup()
        // Release hog mode if active
        if settings.synchronizeSampleRate {
            dacManager.disableHogMode()
        }
    }
    
    // MARK: - Engine Setup
    
    private func initializeBASSEngine() {
        // Ensure we have the current default device
        dacManager.refreshDevice()
        
        // Enable DAC/Hog mode with sample rate synchronization if requested
        if settings.synchronizeSampleRate {
            if dacManager.enableHogMode() {
                Logger.info("Sample rate synchronization enabled - exclusive audio access active")
                if let deviceName = dacManager.getDeviceName() {
                    Logger.info("Hogged device: \(deviceName)")
                }
            } else {
                Logger.warning("Failed to enable sample rate synchronization, continuing with normal mode")
            }
        }
        
        // Get current device sample rate (let device decide, don't force it)
        let deviceSampleRate = dacManager.getCurrentDeviceSampleRate()
        let sampleRate = DWORD(deviceSampleRate)
        let flags: DWORD = 0
        
        // Find the BASS device that matches our CoreAudio device
        let deviceNumber = settings.synchronizeSampleRate ? findMatchingBASSDevice() : -1
        
        let result = BASS_Init(deviceNumber, sampleRate, flags, nil, nil)
        
        if result == 0 {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("BASS initialization failed with error: \(errorCode)")
            isInitialized = false
            
            // Disable hog mode if initialization failed
            if settings.synchronizeSampleRate {
                dacManager.disableHogMode()
            }
        } else {
            Logger.info("BASS audio engine initialized successfully")
            Logger.info("BASS Device: \(deviceNumber), Sample rate: \(Int(deviceSampleRate)) Hz, Buffer: \(settings.bufferLength) ms")
            if settings.synchronizeSampleRate {
                Logger.info("Sample rate synchronization: Enabled - will match each track's sample rate")
            }
            isInitialized = true
            
            // Apply user configuration
            applyAudioSettings()
            
            // Load plugins for extended format support
            loadPlugins()
        }
    }
    
    /// Find the BASS device number that matches our CoreAudio device
    private func findMatchingBASSDevice() -> Int32 {
        guard let targetDeviceName = dacManager.getDeviceName() else {
            Logger.warning("Could not get device name, using default device")
            return -1
        }
        
        Logger.debug("Looking for BASS device matching: \(targetDeviceName)")
        
        // Enumerate BASS devices
        var deviceInfo = BASS_DEVICEINFO()
        var deviceIndex: DWORD = 0
        
        while BASS_GetDeviceInfo(deviceIndex, &deviceInfo) != 0 {
            if let deviceName = deviceInfo.name {
                let bassDeviceName = String(cString: deviceName)
                Logger.debug("BASS device \(deviceIndex): \(bassDeviceName), enabled: \(deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED) != 0)")
                
                // Check if this BASS device matches our CoreAudio device
                // Match by exact name or if one contains the other
                let namesMatch = bassDeviceName == targetDeviceName || 
                                bassDeviceName.contains(targetDeviceName) || 
                                targetDeviceName.contains(bassDeviceName)
                
                if namesMatch && deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED) != 0 {
                    Logger.info("Found matching BASS device: \(deviceIndex) - \(bassDeviceName)")
                    return Int32(deviceIndex)
                }
            }
            deviceIndex += 1
        }
        
        // If no exact match found, try the "Default" device as fallback
        deviceIndex = 0
        while BASS_GetDeviceInfo(deviceIndex, &deviceInfo) != 0 {
            if let deviceName = deviceInfo.name {
                let bassDeviceName = String(cString: deviceName)
                if bassDeviceName == "Default" && deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED) != 0 {
                    Logger.info("Using BASS Default device as fallback: \(deviceIndex)")
                    return Int32(deviceIndex)
                }
            }
            deviceIndex += 1
        }
        
        // If no match found at all, use device -1 (system default)
        Logger.warning("No matching BASS device found for '\(targetDeviceName)', using system default")
        return -1
    }
    
    /// Apply global audio settings from AudioSettings
    /// These settings affect the BASS engine globally
    private func applyAudioSettings() {
        // BASS_CONFIG_BUFFER - Playback buffer length in milliseconds
        BASS_SetConfig(DWORD(BASS_CONFIG_BUFFER), DWORD(settings.bufferLength))
        
        // BASS_CONFIG_FLOATDSP - Always use floating-point for best quality
        BASS_SetConfig(DWORD(BASS_CONFIG_FLOATDSP), 1)
        
        // BASS_CONFIG_SRC - Sample rate conversion quality
        // Always use high quality as fallback, even in sync mode
        // When device rate matches track rate, no resampling occurs anyway (bit-perfect)
        // This is a safety net if device rate switch fails
        BASS_SetConfig(DWORD(BASS_CONFIG_SRC), 4) // 64-point sinc interpolation
        
        if settings.synchronizeSampleRate {
            Logger.debug("Applied audio settings: buffer=\(settings.bufferLength)ms, sync mode (device rate will match tracks)")
        } else {
            Logger.debug("Applied audio settings: buffer=\(settings.bufferLength)ms, SRC quality=4 (64-point sinc)")
        }
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
            guard let self = self else { return }
            
            // Handle sample rate synchronization changes
            if self.settings.synchronizeSampleRate && !self.dacManager.isInHogMode() {
                _ = self.dacManager.enableHogMode()
            } else if !self.settings.synchronizeSampleRate && self.dacManager.isInHogMode() {
                self.dacManager.disableHogMode()
            }
            
            self.applyAudioSettings()
            self.applyChannelSettings()
        }
        
        // Device change notifications
        NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            if let device = notification.object as? AudioOutputDevice {
                Logger.info("Audio device changed notification received: \(device.name)")
                self.handleDeviceChange(to: device)
            }
        }
    }
    
    /// Handle audio device change - move streams to new device
    private func handleDeviceChange(to device: AudioOutputDevice) {
        Logger.info("Handling device change to: \(device.name)")
        
        // Find the BASS device number that matches the new CoreAudio device
        let bassDeviceNumber = findMatchingBASSDeviceForID(device.id)
        
        if bassDeviceNumber == -1 {
            Logger.error("Could not find matching BASS device for: \(device.name)")
            return
        }
        
        // Initialize the new device if not already initialized
        let deviceSampleRate = device.sampleRate
        let sampleRate = DWORD(deviceSampleRate)
        let flags: DWORD = 0
        
        // Check if device is already initialized, if not initialize it
        var deviceInfo = BASS_DEVICEINFO()
        if BASS_GetDeviceInfo(DWORD(bassDeviceNumber), &deviceInfo) != 0 {
            if deviceInfo.flags & DWORD(BASS_DEVICE_INIT) == 0 {
                // Device not initialized, initialize it
                Logger.info("Initializing new BASS device: \(bassDeviceNumber)")
                let result = BASS_Init(bassDeviceNumber, sampleRate, flags, nil, nil)
                if result == 0 {
                    let errorCode = BASS_ErrorGetCode()
                    Logger.error("Failed to initialize new device: \(errorCode)")
                    return
                }
                // Apply settings to new device
                applyAudioSettings()
            }
        }
        
        // Update BASS to use the new device as current
        BASS_SetDevice(DWORD(bassDeviceNumber))
        
        // Try to move streams, but if it fails, we'll need to reload
        var streamMovedSuccessfully = false
        
        if currentStream != 0 {
            let result = BASS_ChannelSetDevice(currentStream, DWORD(bassDeviceNumber))
            if result != 0 {
                Logger.info("✓ Moved current stream to new device")
                streamMovedSuccessfully = true
            } else {
                let errorCode = BASS_ErrorGetCode()
                Logger.warning("Failed to move current stream: \(errorCode) - will need to reload")
            }
        }
        
        // Move preloaded stream to new device
        if nextStream != 0 {
            let result = BASS_ChannelSetDevice(nextStream, DWORD(bassDeviceNumber))
            if result != 0 {
                Logger.debug("✓ Moved preloaded stream to new device")
            } else {
                let errorCode = BASS_ErrorGetCode()
                Logger.warning("Failed to move preloaded stream: \(errorCode)")
                // Clear the preloaded stream if it couldn't be moved
                BASS_StreamFree(nextStream)
                nextStream = 0
            }
        }
        
        Logger.info("Device change complete: now using BASS device \(bassDeviceNumber)")
        
        // Notify that device change is complete and whether stream needs reloading
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioDeviceChangeComplete,
                object: nil,
                userInfo: ["needsReload": !streamMovedSuccessfully]
            )
        }
    }
    
    /// Find BASS device number for a specific CoreAudio device ID
    private func findMatchingBASSDeviceForID(_ deviceID: AudioDeviceID) -> Int32 {
        guard let targetDeviceName = dacManager.getDeviceName() else {
            Logger.warning("Could not get device name")
            return -1
        }
        
        Logger.debug("Looking for BASS device matching ID \(deviceID): \(targetDeviceName)")
        
        // Enumerate BASS devices
        var deviceInfo = BASS_DEVICEINFO()
        var deviceIndex: DWORD = 0
        
        while BASS_GetDeviceInfo(deviceIndex, &deviceInfo) != 0 {
            if let deviceName = deviceInfo.name {
                let bassDeviceName = String(cString: deviceName)
                
                // Match by name
                let namesMatch = bassDeviceName == targetDeviceName || 
                                bassDeviceName.contains(targetDeviceName) || 
                                targetDeviceName.contains(bassDeviceName)
                
                if namesMatch && deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED) != 0 {
                    Logger.info("Found matching BASS device: \(deviceIndex) - \(bassDeviceName)")
                    return Int32(deviceIndex)
                }
            }
            deviceIndex += 1
        }
        
        Logger.warning("No matching BASS device found for '\(targetDeviceName)'")
        return -1
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
    
    func load(url: URL, trackSampleRate: Int? = nil) -> Bool {
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
        
        // Create stream from file first to get actual sample rate
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
        
        // Get stream info to determine actual sample rate
        if let streamInfo = getStreamInfo() {
            Logger.info("Loaded track: \(url.lastPathComponent)")
            Logger.info("  Stream: \(streamInfo.frequency) Hz, \(streamInfo.channels) channels")
            
            // CRITICAL: Switch device sample rate to match track for bit-perfect playback
            // Why this is necessary:
            // - Audio devices operate at a specific sample rate (e.g., 44.1kHz, 48kHz, 96kHz)
            // - If device is at 44.1kHz and track is 96kHz, BASS will resample (quality loss)
            // - By switching device to track's rate, BASS outputs directly without resampling
            // - This is the ONLY way to achieve true bit-perfect playback
            if settings.synchronizeSampleRate {
                let targetRate = Float64(streamInfo.frequency)
                if dacManager.setDeviceSampleRate(targetRate) {
                    Logger.info("  Bit-perfect: Device switched to \(streamInfo.frequency) Hz (no resampling)")
                } else {
                    Logger.warning("  Could not switch device rate, BASS will resample")
                }
            }
        }
        
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
    func preloadNext(url: URL, trackSampleRate: Int? = nil) -> Bool {
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
    func switchToPreloadedTrack(volume: Float, trackSampleRate: Int? = nil) -> Bool {
        guard nextStream != 0 else {
            Logger.error("No pre-loaded track available")
            return false
        }
        
        // Get next stream's sample rate and switch device if needed
        if settings.synchronizeSampleRate {
            var info = BASS_CHANNELINFO()
            if BASS_ChannelGetInfo(nextStream, &info) != 0 {
                let targetRate = Float64(info.freq)
                _ = dacManager.setDeviceSampleRate(targetRate)
            }
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
        
        // Get bit depth from flags
        let bitDepth = getBitDepth(from: info.flags)
        
        return BASSStreamInfo(
            frequency: Int(info.freq),
            channels: Int(info.chans),
            bitrate: Int(BASS_StreamGetFilePosition(currentStream, DWORD(BASS_FILEPOS_END))),
            bitDepth: bitDepth
        )
    }
    
    /// Get bit depth from BASS channel flags
    private func getBitDepth(from flags: DWORD) -> Int {
        if flags & DWORD(BASS_SAMPLE_FLOAT) != 0 {
            return 32 // Float is 32-bit
        } else if flags & DWORD(BASS_SAMPLE_8BITS) != 0 {
            return 8
        } else {
            return 16 // Default is 16-bit
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stop()
        
        // Release hog mode if active
        if settings.synchronizeSampleRate && dacManager.isInHogMode() {
            dacManager.disableHogMode()
        }
        
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
    let bitDepth: Int
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

