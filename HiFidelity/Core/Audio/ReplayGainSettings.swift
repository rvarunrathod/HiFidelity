//
//  ReplayGainSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 21/12/25.
//

import Foundation
import Combine

/// ReplayGain settings and calculation
/// Implements replay gain normalization for consistent playback loudness
class ReplayGainSettings: ObservableObject {
    static let shared = ReplayGainSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Properties
    
    /// Enable/disable replay gain
    @Published var isEnabled: Bool {
        didSet {
            save(isEnabled, forKey: .enabled)
            postNotification()
        }
    }
    
    /// Replay gain mode: track or album
    @Published var mode: ReplayGainMode {
        didSet {
            save(mode.rawValue, forKey: .mode)
            postNotification()
        }
    }
    
    /// Loudness source preference
    @Published var source: LoudnessSource {
        didSet {
            save(source.rawValue, forKey: .source)
            postNotification()
        }
    }
    
    // MARK: - Settings Keys
    
    private enum SettingsKey: String {
        case enabled
        case mode
        case source
        
        var fullKey: String {
            return "replayGain.\(rawValue)"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize with default values
        self.isEnabled = false
        self.mode = .track
        self.source = .automatic
        
        // Load saved settings
        loadSettings()
    }
    
    private func loadSettings() {
        self.isEnabled = defaults.bool(forKey: SettingsKey.enabled.fullKey)
        
        if let modeString = defaults.string(forKey: SettingsKey.mode.fullKey),
           let mode = ReplayGainMode(rawValue: modeString) {
            self.mode = mode
        }
        
        if let sourceString = defaults.string(forKey: SettingsKey.source.fullKey),
           let source = LoudnessSource(rawValue: sourceString) {
            self.source = source
        }
    }
    
    // MARK: - UserDefaults Helpers
    
    private func save<T>(_ value: T, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.fullKey)
    }
    
    private func postNotification() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ReplayGainSettingsChanged"),
            object: nil
        )
    }
    
    // MARK: - Replay Gain Calculation
    
    /// Calculate the volume adjustment for a track
    /// - Parameter track: The track to calculate gain for
    /// - Returns: Linear volume multiplier (0.0 to 1.0+)
    func calculateGainMultiplier(for track: Track) -> Float {
        guard isEnabled else { return 1.0 }
        
        // Apply source preference
        switch source {
        case .automatic:
            // Priority 1: Use R128 loudness if available (more accurate)
            if let r128Loudness = track.r128IntegratedLoudness {
                return calculateR128Multiplier(loudness: r128Loudness)
            }
            // Priority 2: Fall back to traditional ReplayGain tags
            return calculateReplayGainMultiplier(for: track)
            
        case .r128Only:
            // Use only R128 data
            if let r128Loudness = track.r128IntegratedLoudness {
                return calculateR128Multiplier(loudness: r128Loudness)
            }
            Logger.debug("No R128 data for track: \(track.title)")
            return 1.0
            
        case .replayGainOnly:
            // Use only ReplayGain tags
            return calculateReplayGainMultiplier(for: track)
        }
    }
    
    private func calculateR128Multiplier(loudness: Double) -> Float {
        let targetLoudness: Double = -18.0 // LUFS target for music
        let gainDB = targetLoudness - loudness
        let multiplier = pow(10.0, gainDB / 20.0)
        let clampedMultiplier = max(0.01, min(10.0, multiplier))
        
        Logger.debug("R128 gain: \(String(format: "%.1f", loudness)) LUFS → \(String(format: "%.1f", gainDB)) dB (×\(String(format: "%.3f", clampedMultiplier)))")
        
        return Float(clampedMultiplier)
    }
    
    private func calculateReplayGainMultiplier(for track: Track) -> Float {
        let gainString: String?
        switch mode {
        case .track:
            gainString = track.extendedMetadata?.replayGainTrack
        case .album:
            // Prefer album gain, fall back to track gain
            gainString = track.extendedMetadata?.replayGainAlbum ?? track.extendedMetadata?.replayGainTrack
        }
        
        guard let gainString = gainString else {
            Logger.debug("No ReplayGain data for track: \(track.title)")
            return 1.0
        }
        
        // Parse the gain value (e.g., "-4.52 dB" or "+3.21 dB")
        guard let gainDB = parseGainValue(gainString) else {
            Logger.warning("Failed to parse replay gain value: \(gainString)")
            return 1.0
        }
        
        // Convert dB to linear multiplier: multiplier = 10^(dB/20)
        let multiplier = pow(10.0, gainDB / 20.0)
        
        // Clamp to reasonable range (0.01 to 10.0)
        let clampedMultiplier = max(0.01, min(10.0, multiplier))
        
        Logger.debug("ReplayGain: \(gainDB) dB (×\(String(format: "%.3f", clampedMultiplier)))")
        
        return Float(clampedMultiplier)
    }
    
    /// Parse a replay gain value string to dB
    /// Handles formats like: "-4.52 dB", "+3.21 dB", "3.21", "-4.52"
    private func parseGainValue(_ value: String) -> Double? {
        // Remove whitespace and convert to uppercase
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Remove "dB" suffix if present
        let numberPart = cleaned.replacingOccurrences(of: "DB", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse as double
        return Double(numberPart)
    }
    
    // MARK: - Reset
    
    func resetToDefaults() {
        isEnabled = false
        mode = .track
        source = .automatic
        
        Logger.info("ReplayGain settings reset to defaults")
    }
}

// MARK: - Replay Gain Mode

enum ReplayGainMode: String, CaseIterable {
    case track = "track"
    case album = "album"
    
    var displayName: String {
        switch self {
        case .track:
            return "Track Gain"
        case .album:
            return "Album Gain"
        }
    }
    
    var description: String {
        switch self {
        case .track:
            return "Normalize each track individually"
        case .album:
            return "Preserve album dynamics"
        }
    }
}

// MARK: - Loudness Source

enum LoudnessSource: String, CaseIterable {
    case automatic = "automatic"
    case r128Only = "r128Only"
    case replayGainOnly = "replayGainOnly"
    
    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic (Prefer R128)"
        case .r128Only:
            return "R128 Only"
        case .replayGainOnly:
            return "ReplayGain Tags Only"
        }
    }
    
    var description: String {
        switch self {
        case .automatic:
            return "Use R128 if available, fall back to ReplayGain tags"
        case .r128Only:
            return "Only use R128 loudness analysis"
        case .replayGainOnly:
            return "Only use ReplayGain tags from metadata"
        }
    }
}
