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
    }
    
    // MARK: - Engine Setup
    
    private func initializeBASSEngine() {
        dacManager.refreshDevice()
        
        // Enable hog mode if sample rate synchronization is enabled
        // DACManager will handle the hog mode and notify us to reacquire
        if settings.synchronizeSampleRate {
            _ = dacManager.enableHogMode()
        }
        
        // Always use a specific device number (never -1) to prevent auto-switching
        // when macOS changes the default device (e.g., when headphones are plugged in)
        let deviceNumber = findMatchingBASSDevice()
        let sampleRate = DWORD(dacManager.getCurrentDeviceSampleRate())
        
        let result = BASS_Init(deviceNumber, sampleRate, 0, nil, nil)
        
        if result == 0 {
            Logger.error("BASS initialization failed: \(BASS_ErrorGetCode())")
            isInitialized = false
            
            // Disable hog mode if initialization failed
            if settings.synchronizeSampleRate {
                dacManager.disableHogMode()
            }
            return
        }
        
        isInitialized = true
        
        if let deviceName = dacManager.getDeviceName() {
            Logger.info("BASS initialized: \(deviceName) (device=\(deviceNumber)), rate=\(Int(sampleRate))Hz, buffer=\(settings.bufferLength)ms")
        } else {
            Logger.info("BASS initialized: device=\(deviceNumber), rate=\(Int(sampleRate))Hz, buffer=\(settings.bufferLength)ms")
        }
        
        if settings.synchronizeSampleRate {
            Logger.info("Sample rate synchronization enabled - bit-perfect playback active")
        }

        // Apply user configuration 
        applyAudioSettings()

        // Load plugins for extended format support
        loadPlugins()
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
        
        // BASS_CONFIG_FLOATDSP - Let bit depth depend on source file
        // Not forcing floating-point allows bit-perfect playback at native bit depth
        BASS_SetConfig(DWORD(BASS_CONFIG_FLOATDSP), 0)
        
        // BASS_CONFIG_SRC - Sample rate conversion quality
        // Always use high quality as fallback, even in sync mode
        // When device rate matches track rate, no resampling occurs anyway (bit-perfect)
        // This is a safety net if device rate switch fails
        BASS_SetConfig(DWORD(BASS_CONFIG_SRC), 4) // 64-point sinc interpolation
        
        if settings.synchronizeSampleRate {
            Logger.debug("Applied audio settings: buffer=\(settings.bufferLength)ms, native bit depth, sync mode")
        } else {
            Logger.debug("Applied audio settings: buffer=\(settings.bufferLength)ms, native bit depth, SRC quality=4")
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
        // Audio settings changes (buffer, volume, etc.)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            
            Logger.debug("Audio settings changed - applying updates")
            
            // Handle sample rate synchronization toggle
            if self.settings.synchronizeSampleRate && !self.dacManager.isInHogMode() {
                _ = self.dacManager.enableHogMode()
            } else if !self.settings.synchronizeSampleRate && self.dacManager.isInHogMode() {
                self.dacManager.disableHogMode()
            }
            
            self.applyAudioSettings()
            self.applyChannelSettings()
        }
        
        // Device needs reacquisition (after hog mode enabled)
        NotificationCenter.default.addObserver(
            forName: .audioDeviceNeedsReacquisition,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reacquireDevice()
        }
        
        // Device change notifications
        NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            if let device = notification.object as? AudioOutputDevice {
                Logger.info("Audio device changed: \(device.name)")
                self.handleDeviceChange(to: device)
            }
        }
    }
    
    /// Reacquire BASS device after hog mode is enabled
    private func reacquireDevice() {
        Logger.info("Reacquiring BASS device after hog mode enabled")
        
        let bassDeviceNumber = findMatchingBASSDevice()
        
        // Ensure the device is initialized
        var deviceInfo = BASS_DEVICEINFO()
        if BASS_GetDeviceInfo(DWORD(bassDeviceNumber), &deviceInfo) != 0 {
            if deviceInfo.flags & DWORD(BASS_DEVICE_INIT) == 0 {
                // Initialize device
                let sampleRate = DWORD(dacManager.getCurrentDeviceSampleRate())
                let result = BASS_Init(bassDeviceNumber, sampleRate, 0, nil, nil)
                if result == 0 {
                    Logger.error("Failed to initialize BASS device: \(BASS_ErrorGetCode())")
                    return
                }
                applyAudioSettings()
            }
        }
        
        // Set as current device
        if BASS_SetDevice(DWORD(bassDeviceNumber)) == 0 {
            Logger.error("Failed to bass set device: \(BASS_ErrorGetCode())")
        }
        
        // Move existing streams
        if currentStream != 0 {
            let result = BASS_ChannelSetDevice(currentStream, DWORD(bassDeviceNumber))
            if result == 0 {
                Logger.warning("Failed to move stream: \(BASS_ErrorGetCode())")
            } else {
                Logger.info("✓ Stream moved to reacquired device")
            }
        }
    }
    
    /// Handle audio device change - move streams to new device
    private func handleDeviceChange(to device: AudioOutputDevice) {
        Logger.info("Handling device change to: \(device.name)")
        
        let bassDeviceNumber = findMatchingBASSDeviceForID(device.id)
        guard bassDeviceNumber != -1 else {
            Logger.error("Could not find matching BASS device for: \(device.name)")
            return
        }
        
        // Check if stream was playing before the device change
        let wasPlaying = currentStream != 0 && BASS_ChannelIsActive(currentStream) == DWORD(BASS_ACTIVE_PLAYING)
        if wasPlaying {
            Logger.debug("Stream was playing before device change")
        }
        
        // Initialize device if needed
        var deviceInfo = BASS_DEVICEINFO()
        if BASS_GetDeviceInfo(DWORD(bassDeviceNumber), &deviceInfo) != 0 {
            if deviceInfo.flags & DWORD(BASS_DEVICE_INIT) == 0 {
                Logger.info("Initializing BASS device \(bassDeviceNumber)")
                let result = BASS_Init(bassDeviceNumber, DWORD(device.sampleRate), 0, nil, nil)
                if result == 0 {
                    Logger.error("Failed to initialize new device: \(BASS_ErrorGetCode())")
                    return
                }
                applyAudioSettings()
            }
        }
        
        // Switch to new device
        if BASS_SetDevice(DWORD(bassDeviceNumber)) == 0 {
            Logger.error("Failed to bass set device: \(BASS_ErrorGetCode())")
        }
        Logger.debug("BASS device set to \(bassDeviceNumber)")
        
        // Try to move existing streams
        var streamMovedSuccessfully = false
        
        if currentStream != 0 {
            streamMovedSuccessfully = BASS_ChannelSetDevice(currentStream, DWORD(bassDeviceNumber)) != 0
            Logger.info(streamMovedSuccessfully ? "✓ Stream moved to new device" : "⚠️ Stream move failed - reload needed")
            
            // If stream was moved successfully and was playing, ensure it continues playing on new device
            if streamMovedSuccessfully && wasPlaying {
                // Ensure the output device is started
                if BASS_IsStarted() == 0 {
                    Logger.debug("Starting output on new device")
                    if BASS_Start() == 0 {
                        Logger.warning("Failed to start output device: \(BASS_ErrorGetCode())")
                    }
                }
                
                // Resume playback on the new device
                let playResult = BASS_ChannelPlay(currentStream, 0)
                if playResult != 0 {
                    Logger.info("✓ Resumed playback on new device")
                } else {
                    Logger.error("Failed to resume playback on new device: \(BASS_ErrorGetCode())")
                    streamMovedSuccessfully = false
                }
            }
        } else {
            Logger.debug("No current stream - reload will be needed if track exists")
        }
        
        if nextStream != 0 {
            if BASS_ChannelSetDevice(nextStream, DWORD(bassDeviceNumber)) == 0 {
                BASS_StreamFree(nextStream)
                nextStream = 0
            }
        }
        
        // Post completion notification
        // needsReload is true if stream doesn't exist OR if it exists but couldn't be moved
        let needsReload = !streamMovedSuccessfully
        Logger.info("Posting device change complete: needsReload=\(needsReload)")
        
        NotificationCenter.default.post(
            name: .audioDeviceChangeComplete,
            object: nil,
            userInfo: ["needsReload": needsReload]
        )
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
        
        // Create stream from file first to get actual sample rate
        let path = url.path
        
        currentStream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            path,
            0,
            0,
            DWORD(BASS_STREAM_PRESCAN) // Use native bit depth from source file
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
        
        // CRITICAL: Switch device sample rate to match track for bit-perfect playback
        // Why this is necessary:
        // - Audio devices operate at a specific sample rate (e.g., 44.1kHz, 48kHz, 96kHz)
        // - If device is at 44.1kHz and track is 96kHz, BASS will resample (quality loss)
        // - By switching device to track's rate, BASS outputs directly without resampling
        // - This is the ONLY way to achieve true bit-perfect playback
        if settings.synchronizeSampleRate {
            // Get stream info to determine actual sample rate and bit depth
            if let streamInfo = getStreamInfo() {
                Logger.info("Loaded track: \(url.lastPathComponent)")
                Logger.info("  Stream: \(streamInfo.frequency) Hz, \(streamInfo.channels) channels, \(streamInfo.bitDepth)-bit")
            
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
        
        // Ensure the audio output device is started
        // The output may be paused automatically if the output device becomes unavailable (e.g., disconnected)
        // or after device switches. BASS_Start() resumes the output before playing the channel.
        if BASS_IsStarted() == 0 {
            Logger.debug("Output device is paused/stopped, starting it")
            if BASS_Start() == 0 {
                let errorCode = BASS_ErrorGetCode()
                Logger.warning("Failed to start output device: \(errorCode)")
                // Continue anyway - try to play the channel
            }
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
            DWORD(BASS_STREAM_PRESCAN) // Use native bit depth from source file
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
        
        // Calculate bitrate from file size and duration
        let fileSize = BASS_StreamGetFilePosition(currentStream, DWORD(BASS_FILEPOS_END))
        let duration = getDuration()
        
        // Bitrate in bps = (fileSize in bytes * 8 bits) / duration in seconds
        // Convert to kbps
        let bitrate = duration > 0 ? Int((Double(fileSize) * 8.0) / duration) : 0
        
        return BASSStreamInfo(
            frequency: Int(info.freq),
            channels: Int(info.chans),
            bitrate: bitrate,
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
        
        if isInitialized {
            // Unload plugins
            for plugin in loadedPlugins {
                BASS_PluginFree(plugin)
            }
            loadedPlugins.removeAll()
            
            // Free BASS
            BASS_Free()
            isInitialized = false
            
            // Release hog mode
            if dacManager.isInHogMode() {
                dacManager.disableHogMode()
            }
            
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

