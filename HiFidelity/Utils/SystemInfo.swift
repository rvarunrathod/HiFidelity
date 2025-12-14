//
//  SystemInfo.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import Foundation
import AppKit
import AVFoundation

// MARK: - System Information Utility

/// Utility class to gather and print system, hardware, and audio information
/// for debugging and troubleshooting purposes
final class SystemInfo {
    
    // MARK: - Public API
    
    /// Print all system information at app startup
    static func printStartupInfo() {
        Logger.info("═══════════════════════════════════════════════════════════")
        Logger.info("🎵 HiFidelity - Startup System Information")
        Logger.info("═══════════════════════════════════════════════════════════")
        
        printApplicationInfo()
        printSystemInfo()
        printHardwareInfo()
        printAudioDeviceInfo()
        printStorageInfo()
        printAudioFormatsInfo()
        
        Logger.info("═══════════════════════════════════════════════════════════")
        Logger.info("System information gathering complete")
        Logger.info("═══════════════════════════════════════════════════════════")
    }
    
    // MARK: - Application Information
    
    private static func printApplicationInfo() {
        Logger.info("▶ Application Information:")
        
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? About.appTitle
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? About.appVersion
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? About.appBuild
        let bundleIdentifier = bundle.bundleIdentifier ?? About.bundleIdentifier
        
        Logger.info("  • Name: \(appName)")
        Logger.info("  • Version: \(appVersion)")
        Logger.info("  • Build: \(buildNumber)")
        Logger.info("  • Bundle ID: \(bundleIdentifier)")
        
        // Compilation info
        #if DEBUG
        Logger.info("  • Build Type: Debug")
        #else
        Logger.info("  • Build Type: Release")
        #endif
        
        // Architecture
        #if arch(x86_64)
        Logger.info("  • Architecture: x86_64 (Intel)")
        #elseif arch(arm64)
        Logger.info("  • Architecture: arm64 (Apple Silicon)")
        #else
        Logger.info("  • Architecture: Unknown")
        #endif
    }
    
    // MARK: - System Information
    
    private static func printSystemInfo() {
        Logger.info("▶ System Information:")
        
        let processInfo = ProcessInfo.processInfo
        
        // macOS version
        let osVersion = processInfo.operatingSystemVersion
        Logger.info("  • macOS Version: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        Logger.info("  • macOS Name: \(processInfo.operatingSystemVersionString)")
        
        // System uptime
        let uptime = processInfo.systemUptime
        let uptimeFormatted = formatTimeInterval(uptime)
        Logger.info("  • System Uptime: \(uptimeFormatted)")
        
        
        // Process info
        Logger.info("  • Process ID: \(processInfo.processIdentifier)")
        Logger.info("  • Process Name: \(processInfo.processName)")
    }
    
    // MARK: - Hardware Information
    
    private static func printHardwareInfo() {
        Logger.info("▶ Hardware Information:")
        
        let processInfo = ProcessInfo.processInfo
        
        // CPU information
        let processorCount = processInfo.processorCount
        let activeProcessorCount = processInfo.activeProcessorCount
        Logger.info("  • Processor Cores: \(processorCount) (Active: \(activeProcessorCount))")
        
        // Get CPU brand/model if available
        if let cpuBrand = getCPUBrand() {
            Logger.info("  • Processor Model: \(cpuBrand)")
        }
        
        // Memory information
        let physicalMemory = processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / 1_073_741_824.0 // Convert bytes to GB
        Logger.info("  • Physical Memory: \(String(format: "%.2f", memoryGB)) GB")
        
        // Current memory usage
        if let memoryUsage = getMemoryUsage() {
            Logger.info("  • App Memory Usage: \(memoryUsage)")
        }
        
        // Hardware model
        if let model = getHardwareModel() {
            Logger.info("  • Hardware Model: \(model)")
        }
        
    }
    
    // MARK: - Audio Device Information
    
    private static func printAudioDeviceInfo() {
        Logger.info("▶ Audio Device Information:")
        
        // Output devices
        let outputDevices = getAudioDevices(isInput: false)
        Logger.info("  • Audio Output Devices: \(outputDevices.count)")
        for (index, device) in outputDevices.enumerated() {
            let prefix = device.isDefault ? "    [DEFAULT]" : "           "
            Logger.info("\(prefix) \(index + 1). \(device.name)")
            Logger.info("              UID: \(Int(device.uid))")
            if let sampleRate = device.sampleRate {
                Logger.info("              Sample Rate: \(Int(sampleRate)) Hz")
            }
            if let channels = device.channels {
                Logger.info("              Channels: \(channels)")
            }
        }
        
        // Input devices
        let inputDevices = getAudioDevices(isInput: true)
        Logger.info("  • Audio Input Devices: \(inputDevices.count)")
        for (index, device) in inputDevices.enumerated() {
            let prefix = device.isDefault ? "    [DEFAULT]" : "           "
            Logger.info("\(prefix) \(index + 1). \(device.name)")
            Logger.info("              UID: \(Int(device.uid))")
            if let sampleRate = device.sampleRate {
                Logger.info("              Sample Rate: \(Int(sampleRate)) Hz")
            }
            if let channels = device.channels {
                Logger.info("              Channels: \(channels)")
            }
        }
    }
    
    // MARK: - Storage Information
    
    private static func printStorageInfo() {
        Logger.info("▶ Storage Information:")
        
        // App support directory
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleID = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
            let appDirectory = appSupportURL.appendingPathComponent(bundleID)
            Logger.info("  • App Support Directory: \(appDirectory.path)")
            
            // Check if directory exists and get size
            if FileManager.default.fileExists(atPath: appDirectory.path) {
                if let size = getDirectorySize(url: appDirectory) {
                    Logger.info("    Size: \(formatBytes(size))")
                }
            }
        }
        
        // Log file location
        if let logURL = Logger.logFileURL {
            Logger.info("  • Log File: \(logURL.path)")
            if let size = getFileSize(url: logURL) {
                Logger.info("    Size: \(formatBytes(size))")
            }
        }
        
        // Available disk space
        if let home = FileManager.default.urls(for: .userDirectory, in: .userDomainMask).first {
            if let availableSpace = getAvailableDiskSpace(at: home) {
                Logger.info("  • Available Disk Space: \(formatBytes(availableSpace))")
            }
        }
    }
    
    // MARK: - Audio Formats Information
    
    private static func printAudioFormatsInfo() {
        Logger.info("▶ Supported Audio Formats:")
        
        let formats = AudioFormat.supportedMusicFormat
        let formatsPerLine = 8
        var currentLine: [String] = []
        
        for (index, format) in formats.enumerated() {
            currentLine.append(format.uppercased())
            
            if (index + 1) % formatsPerLine == 0 || index == formats.count - 1 {
                Logger.info("  • \(currentLine.joined(separator: ", "))")
                currentLine.removeAll()
            }
        }
        
        Logger.info("  • Total Formats: \(formats.count)")
    }
    
    // MARK: - Helper Methods
    
    private static func getCPUBrand() -> String? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        return String(cString: machine).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func getHardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }
    
    private static func getMemoryUsage() -> String? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return nil }
        
        let usedMemory = Double(info.resident_size) / 1_048_576.0 // Convert to MB
        return String(format: "%.2f MB", usedMemory)
    }
    
    private static func getAudioDevices(isInput: Bool) -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        // Get the default device
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var defaultDeviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &size,
            &defaultDeviceID
        )
        
        guard status == noErr else { return devices }
        
        // Get all devices
        propertyAddress.mSelector = kAudioHardwarePropertyDevices
        var devicesSize: UInt32 = 0
        
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &devicesSize
        ) == noErr else { return devices }
        
        let deviceCount = Int(devicesSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &devicesSize,
            &deviceIDs
        ) == noErr else { return devices }
        
        // Filter and get info for each device
        for deviceID in deviceIDs {
            // Check if device has the right streams (input/output)
            propertyAddress.mSelector = isInput ? kAudioDevicePropertyStreams : kAudioDevicePropertyStreams
            propertyAddress.mScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
            
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }
            
            // Get device name
            propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
            propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
            var deviceName: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            
            guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &nameSize, &deviceName) == noErr,
                  let deviceNameRef = deviceName?.takeRetainedValue() as String? else { continue }
            
            // Get sample rate
            propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
            var sampleRate: Float64 = 0
            var sampleRateSize = UInt32(MemoryLayout<Float64>.size)
            let hasSampleRate = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &sampleRateSize, &sampleRate) == noErr
            
            // Get channel count
            propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
            propertyAddress.mScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
            var bufferListSize: UInt32 = 0
            
            var channels: Int? = nil
            if AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &bufferListSize) == noErr {
                let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferList.deallocate() }
                
                if AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &bufferListSize, bufferList) == noErr {
                    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                    channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
                }
            }
            
            devices.append(AudioDeviceInfo(
                uid: deviceID,
                name: deviceNameRef,
                isDefault: deviceID == defaultDeviceID,
                sampleRate: hasSampleRate ? sampleRate : nil,
                channels: channels
            ))
        }
        
        return devices
    }
    
    private static func getDirectorySize(url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    private static func getFileSize(url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else { return nil }
        return fileSize
    }
    
    private static func getAvailableDiskSpace(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }
    
    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter.string(fromByteCount: bytes)
    }
    
    private static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d hours, %d minutes, %d seconds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d minutes, %d seconds", minutes, seconds)
        } else {
            return String(format: "%d seconds", seconds)
        }
    }
}

// MARK: - Supporting Types

private struct AudioDeviceInfo {
    let uid: UInt32
    let name: String
    let isDefault: Bool
    let sampleRate: Float64?
    let channels: Int?
}

