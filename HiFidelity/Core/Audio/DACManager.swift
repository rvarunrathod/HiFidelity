//
//  DACManager.swift
//  HiFidelity
//
//  Created for HiFidelity
//

import Foundation
import CoreAudio
import AudioToolbox
import Combine

/// Represents an audio output device
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let sampleRate: Float64
    let channels: Int
    
    static func == (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages macOS Audio Device (DAC) in Hog Mode for exclusive, bit-perfect playback
/// Hog mode gives the application exclusive access to the audio device
class DACManager: ObservableObject {
    static let shared = DACManager()
    
    @Published private(set) var currentDeviceID: AudioDeviceID = 0
    @Published private(set) var availableDevices: [AudioOutputDevice] = []
    @Published private(set) var currentDevice: AudioOutputDevice?
    @Published private(set) var deviceWasRemoved: Bool = false
    
    private var isHogging = false
    private var deviceListListenerProc: AudioObjectPropertyListenerProc?
    
    private init() {
        currentDeviceID = getDefaultOutputDevice()
        refreshDeviceList()
        setupDeviceChangeListener()
    }
    
    deinit {
        removeDeviceChangeListener()
    }
    
    // MARK: - Device Management
    
    /// Get the default audio output device
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status != noErr {
            Logger.error("Failed to get default output device: \(status)")
            return 0
        }
        
        Logger.debug("Default output device ID: \(deviceID)")
        return deviceID
    }
    
    /// Get current sample rate of the device
    func getCurrentDeviceSampleRate() -> Float64 {
        guard currentDeviceID != 0 else { return 44100 }
        
        var sampleRate = Float64(0)
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        if status != noErr {
            Logger.error("Failed to get device sample rate: \(status)")
            return 44100
        }
        
        return sampleRate
    }
    
    // MARK: - Hog Mode Control
    
    /// Enable hog mode - gives exclusive access to the audio device
    func enableHogMode() -> Bool {
        guard currentDeviceID != 0 else {
            Logger.error("No valid audio device")
            return false
        }
        
        guard !isHogging else {
            Logger.debug("Hog mode already enabled")
            return true
        }
        
        var hogPID = pid_t(getpid())
        let propertySize = UInt32(MemoryLayout<pid_t>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            propertySize,
            &hogPID
        )
        
        if status != noErr {
            Logger.error("Failed to enable hog mode: \(status)")
            return false
        }
        
        isHogging = true
        Logger.info("Hog mode enabled on device \(currentDeviceID) - BASS handles sample rate conversion")        
        // Notify that device needs reacquisition in BASS
        NotificationCenter.default.post(name: .audioDeviceNeedsReacquisition, object: nil)
        
        return true
    }
    
    /// Disable hog mode - releases exclusive access
    func disableHogMode() {
        guard currentDeviceID != 0, isHogging else { return }
        
        var hogPID = pid_t(-1)  // -1 releases hog mode
        let propertySize = UInt32(MemoryLayout<pid_t>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            propertySize,
            &hogPID
        )
        
        if status == noErr {
            isHogging = false
            Logger.info("Hog mode disabled")
        } else {
            Logger.error("Failed to disable hog mode: \(status)")
        }
    }
    
    // MARK: - Sample Rate Control
    
    /// Set the device sample rate to match track for bit-perfect playback
    func setDeviceSampleRate(_ sampleRate: Float64) -> Bool {
        guard currentDeviceID != 0 else {
            Logger.error("No valid audio device")
            return false
        }
        
        // Check if already at desired sample rate
        let currentRate = getCurrentDeviceSampleRate()
        if abs(currentRate - sampleRate) < 0.1 {
            Logger.debug("Device already at \(Int(sampleRate)) Hz")
            return true
        }
        
        var newRate = sampleRate
        let propertySize = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            propertySize,
            &newRate
        )
        
        if status != noErr {
            Logger.error("Failed to set device sample rate to \(Int(sampleRate)) Hz: \(status)")
            return false
        }
        
        Logger.info("Device sample rate switched to \(Int(sampleRate)) Hz for bit-perfect playback")
        
        // Give the device a moment to stabilize
        Thread.sleep(forTimeInterval: 0.05)
        
        return true
    }
    
    /// Get available sample rates for the current device
    func getAvailableSampleRates() -> [Float64] {
        guard currentDeviceID != 0 else { return [44100, 48000, 88200, 96000, 176400, 192000] }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            return [44100, 48000, 88200, 96000, 176400, 192000]
        }
        
        let count = Int(propertySize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        
        status = AudioObjectGetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &ranges
        )
        
        guard status == noErr else {
            return [44100, 48000, 88200, 96000, 176400, 192000]
        }
        
        // Extract unique sample rates
        var sampleRates: [Float64] = []
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                sampleRates.append(range.mMinimum)
            }
        }
        
        return sampleRates.sorted()
    }
    
    // MARK: - Status
    
    func isInHogMode() -> Bool {
        return isHogging
    }
    
    func getDeviceID() -> AudioDeviceID {
        return currentDeviceID
    }
    
    /// Get the device name for matching with BASS devices
    func getDeviceName() -> String? {
        guard currentDeviceID != 0 else { return nil }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceName
        )
        
        guard status == noErr else {
            Logger.error("Failed to get device name: \(status)")
            return nil
        }
        
        return deviceName as String
    }
    
    /// Get device UID for matching with BASS
    func getDeviceUID() -> String? {
        guard currentDeviceID != 0 else { return nil }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceUID: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceUID
        )
        
        guard status == noErr else {
            Logger.error("Failed to get device UID: \(status)")
            return nil
        }
        
        return deviceUID as String
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioDeviceChanged = Notification.Name("AudioDeviceChanged")
    static let audioDeviceRemoved = Notification.Name("AudioDeviceRemoved")
    static let audioDeviceChangeComplete = Notification.Name("AudioDeviceChangeComplete")
    static let audioDeviceNeedsReacquisition = Notification.Name("AudioDeviceNeedsReacquisition")
}

extension DACManager {
    // MARK: - Device Change Monitoring
    
    /// Set up listener for device list changes (hot-plugging)
    private func setupDeviceChangeListener() {
        // Listen for device list changes (add/remove)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listenerProc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
            guard let clientData = clientData else { return noErr }
            let manager = Unmanaged<DACManager>.fromOpaque(clientData).takeUnretainedValue()
            
            DispatchQueue.main.async {
                manager.handleDeviceListChanged()
            }
            
            return noErr
        }
        
        deviceListListenerProc = listenerProc
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            selfPtr
        )
    }
    
    /// Remove device change listener
    private func removeDeviceChangeListener() {
        guard let listenerProc = deviceListListenerProc else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            selfPtr
        )
    }
    
    /// Handle device list changes (hot-plugging)
    private func handleDeviceListChanged() {
        Logger.info("Audio device list changed (device added/removed)")
        
        // Get previous device list
        let previousDeviceIDs = Set(availableDevices.map { $0.id })
        Logger.debug("Previous device IDs: \(previousDeviceIDs), current device ID: \(currentDeviceID)")
        
        // Refresh device list
        refreshDeviceList()
        
        // Get new device list
        let currentDeviceIDs = Set(availableDevices.map { $0.id })
        Logger.debug("Current device IDs: \(currentDeviceIDs)")
        
        // Check for removed devices
        let removedDevices = previousDeviceIDs.subtracting(currentDeviceIDs)
        
        // Check if current device was removed
        // Handle two cases: 1) explicit device ID removed, 2) currentDeviceID is 0/invalid and devices were removed
        if (currentDeviceID != 0 && removedDevices.contains(currentDeviceID)) || 
           (currentDeviceID == 0 && !removedDevices.isEmpty && !previousDeviceIDs.isEmpty) {
            Logger.warning("⚠️ Current audio device (ID: \(currentDeviceID)) was removed or invalid!")
            handleCurrentDeviceRemoved()
        } else if !removedDevices.isEmpty {
            Logger.debug("Removed devices: \(removedDevices) (not current device)")
        }
        
        // Check for added devices
        let addedDevices = currentDeviceIDs.subtracting(previousDeviceIDs)
        if !addedDevices.isEmpty {
            Logger.info("✓ \(addedDevices.count) new audio device(s) detected")
        }
        
        if !removedDevices.isEmpty {
            Logger.info("✗ \(removedDevices.count) audio device(s) removed")
        }
    }
    
    /// Handle current device being removed
    private func handleCurrentDeviceRemoved() {
        // Release hog mode if active (device is gone, just clear the flag)
        let wasHogging = isHogging
        if wasHogging {
            isHogging = false
            Logger.info("Sample rate synchronization disabled - device was removed")
        }
        
        // Update UI state on main thread
        DispatchQueue.main.async { [weak self] in
            self?.deviceWasRemoved = true
            if wasHogging {
                AudioSettings.shared.synchronizeSampleRate = false
            }
        }
        
        // Post notification to stop playback
        NotificationCenter.default.post(
            name: .audioDeviceRemoved,
            object: nil
        )
        
        // Refresh device list to get latest available devices
        refreshDeviceList()
        
        // Get the latest default device from the system
        let defaultDeviceID = getDefaultOutputDevice()
        
        if defaultDeviceID != 0 {
            // Build device info for the new default device
            if let deviceName = getDeviceNameForID(defaultDeviceID),
               let deviceUID = getDeviceUIDForID(defaultDeviceID) {
                
                let sampleRate = getCurrentSampleRateForDevice(defaultDeviceID)
                let channels = getChannelCountForDevice(defaultDeviceID)
                
                let newDevice = AudioOutputDevice(
                    id: defaultDeviceID,
                    name: deviceName,
                    uid: deviceUID,
                    sampleRate: sampleRate,
                    channels: channels
                )
                
                Logger.info("Auto-switching to default device: \(newDevice.name)")
                if wasHogging {
                    Logger.info("Sample rate synchronization was disabled - re-enable manually if needed")
                }
                
                // Update device on main thread (for UI updates) and post notification
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Update to new device (triggers @Published updates for UI)
                    self.currentDeviceID = defaultDeviceID
                    self.currentDevice = newDevice
                    Logger.debug("Updated currentDeviceID to \(defaultDeviceID)")
                    
                    // Wait a bit for device to stabilize, then notify BASS
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        Logger.info("Posting audioDeviceChanged notification for: \(newDevice.name)")
                        NotificationCenter.default.post(name: .audioDeviceChanged, object: newDevice)
                        self?.deviceWasRemoved = false
                    }
                }
            } else {
                // Couldn't get info for "default" device - fallback to first available device
                Logger.warning("Could not get info for default device ID: \(defaultDeviceID), using first available device")
                
                if let firstDevice = availableDevices.first {
                    Logger.info("Auto-switching to first available device: \(firstDevice.name)")
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        self.currentDeviceID = firstDevice.id
                        self.currentDevice = firstDevice
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            Logger.info("Posting audioDeviceChanged notification for: \(firstDevice.name)")
                            NotificationCenter.default.post(name: .audioDeviceChanged, object: firstDevice)
                            self?.deviceWasRemoved = false
                        }
                    }
                } else {
                    Logger.error("No devices available at all!")
                    DispatchQueue.main.async { [weak self] in
                        self?.currentDeviceID = 0
                        self?.currentDevice = nil
                    }
                }
            }
        } else {
            // System returned 0 for default device - wait and retry
            Logger.warning("No default device available yet (ID=0), waiting for system to stabilize...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                
                // Retry getting default device
                let retryDefaultID = self.getDefaultOutputDevice()
                
                if retryDefaultID != 0 {
                    Logger.info("Default device now available: \(retryDefaultID), retrying switch")
                    self.refreshDeviceList()
                    
                    if let newDevice = self.availableDevices.first(where: { $0.id == retryDefaultID }) {
                        self.currentDeviceID = retryDefaultID
                        self.currentDevice = newDevice
                        Logger.info("Successfully switched to: \(newDevice.name)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            NotificationCenter.default.post(name: .audioDeviceChanged, object: newDevice)
                            self?.deviceWasRemoved = false
                        }
                    }
                } else if let firstDevice = self.availableDevices.first {
                    // Still no default, use first available
                    Logger.warning("Still no default device, using first available: \(firstDevice.name)")
                    self.currentDeviceID = firstDevice.id
                    self.currentDevice = firstDevice
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        NotificationCenter.default.post(name: .audioDeviceChanged, object: firstDevice)
                        self?.deviceWasRemoved = false
                    }
                } else {
                    Logger.error("No devices available after retry")
                }
            }
        }
    }
    
    /// Update device when needed (called manually) - only used at app startup
    func updateDevice() {
        currentDeviceID = getDefaultOutputDevice()
    }
    
    /// Refresh device info (without changing user's selected device)
    func refreshDevice() {
        // Don't change currentDeviceID - preserve user's selection
        // Just refresh the device list to get updated info
        refreshDeviceList()
    }
    
    // MARK: - Device Enumeration
    
    /// Get all available audio output devices
    func getAllOutputDevices() -> [AudioOutputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            Logger.error("Failed to get device list size: \(status)")
            return []
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard status == noErr else {
            Logger.error("Failed to get device list: \(status)")
            return []
        }
        
        var outputDevices: [AudioOutputDevice] = []
        
        for deviceID in deviceIDs {
            // Check if device has output streams
            if !hasOutputStreams(deviceID: deviceID) {
                continue
            }
            
            guard let name = getDeviceNameForID(deviceID),
                  let uid = getDeviceUIDForID(deviceID) else {
                continue
            }
            
            let sampleRate = getCurrentSampleRateForDevice(deviceID)
            let channels = getChannelCountForDevice(deviceID)
            
            let device = AudioOutputDevice(
                id: deviceID,
                name: name,
                uid: uid,
                sampleRate: sampleRate,
                channels: channels
            )
            
            outputDevices.append(device)
        }
        
        return outputDevices
    }
    
    /// Check if device has output streams
    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr, propertySize > 0 else {
            return false
        }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferList
        )
        
        guard getStatus == noErr else {
            return false
        }
        
        return bufferList.pointee.mNumberBuffers > 0
    }
    
    /// Get device name for a specific device ID
    private func getDeviceNameForID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceName
        )
        
        return status == noErr ? (deviceName as String) : nil
    }
    
    /// Get device UID for a specific device ID
    private func getDeviceUIDForID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceUID: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceUID
        )
        
        return status == noErr ? (deviceUID as String) : nil
    }
    
    /// Get current sample rate for a specific device
    private func getCurrentSampleRateForDevice(_ deviceID: AudioDeviceID) -> Float64 {
        var sampleRate = Float64(0)
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        return status == noErr ? sampleRate : 44100
    }
    
    /// Get number of output channels for a specific device
    private func getChannelCountForDevice(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr, propertySize > 0 else {
            return 2 // Default to stereo
        }
        
        let bufferListSize = Int(propertySize)
        let bufferListPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferListSize)
        defer { bufferListPointer.deallocate() }
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferListPointer
        )
        
        guard status == noErr else {
            return 2 // Default to stereo
        }
        
        let bufferList = bufferListPointer.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0.pointee }
        
        var totalChannels = 0
        let numBuffers = Int(bufferList.mNumberBuffers)
        
        if numBuffers > 0 {
            let buffersPointer = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(&(bufferListPointer.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0 }.pointee))
            )
            
            for buffer in buffersPointer {
                totalChannels += Int(buffer.mNumberChannels)
            }
        }
        
        return totalChannels > 0 ? totalChannels : 2
    }
    
    /// Refresh the list of available devices
    func refreshDeviceList() {
        availableDevices = getAllOutputDevices()
        currentDevice = availableDevices.first { $0.id == currentDeviceID }
        
        // Only update to system default if we're in an invalid state (device is 0 or doesn't exist)
        // Don't follow system default changes - preserve user's device selection
        if currentDeviceID == 0 {
            let defaultID = getDefaultOutputDevice()
            if defaultID != 0 {
                Logger.debug("No device selected, using system default: \(defaultID)")
                currentDeviceID = defaultID
                currentDevice = availableDevices.first { $0.id == defaultID }
            }
        } else if currentDevice == nil {
            // Current device no longer exists (was removed)
            // This will be handled by handleCurrentDeviceRemoved, don't auto-switch here
            Logger.debug("Current device ID \(currentDeviceID) no longer available")
        }
        
        Logger.debug("Found \(availableDevices.count) output devices, current: \(currentDevice?.name ?? "none")")
    }
    
    /// Switch to a different audio device
    func switchToDevice(_ device: AudioOutputDevice) -> Bool {
        guard device.id != currentDeviceID else {
            Logger.debug("Already using device: \(device.name)")
            return true
        }
        
        Logger.info("Switching to device: \(device.name)")
        
        // Disable hog mode on old device if active
        // User must manually re-enable sample rate synchronization for the new device
        let wasHogging = isHogging
        if wasHogging {
            disableHogMode()
            Logger.info("Sample rate synchronization disabled - re-enable manually if needed for new device")
        }
        
        // Update device state on main thread and notify observers
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update @Published properties (triggers UI updates)
            self.currentDeviceID = device.id
            self.currentDevice = device
            
            // Update settings if hog mode was disabled
            if wasHogging {
                AudioSettings.shared.synchronizeSampleRate = false
            }
            
            // Notify BASS to move streams (on main thread)
            Logger.debug("Posting audioDeviceChanged notification for: \(device.name)")
            NotificationCenter.default.post(name: .audioDeviceChanged, object: device)
        }
        
        return true
    }
}

