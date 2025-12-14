//
//  AudioSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 15/11/25.
//

import Foundation
import Combine

/// Audio settings manager with user-friendly options
/// Settings are applied at runtime without requiring restart
class AudioSettings: ObservableObject {
    static let shared = AudioSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Properties
    
    // Playback Settings (applied at runtime via BASS_ChannelSetAttribute)
    @Published var playbackVolume: Double {
        didSet { save(playbackVolume, forKey: .playbackVolume) }
    }
    
    // Audio Quality Settings (BASS_SetConfig - applied immediately)
    @Published var bufferLength: Int {
        didSet { 
            save(bufferLength, forKey: .bufferLength)
            postNotification()
        }
    }
    
    // DAC/Hog Mode with Native Sample Rate Synchronization
    // Not persisted - resets on app restart for safety
    @Published var synchronizeSampleRate: Bool = false {
        didSet {
            postNotification()
        }
    }
    
    // MARK: - Settings Keys
    
    private enum SettingsKey: String {
        case playbackVolume
        case gaplessPlayback
        case bufferLength
        
        var fullKey: String {
            return "audio.\(rawValue)"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Initialize with default values
        self.playbackVolume = 0.7
        self.bufferLength = 500
        
        // Load saved settings
        loadSettings()
    }
    
    private func loadSettings() {
        self.playbackVolume = defaults.object(forKey: SettingsKey.playbackVolume.fullKey) as? Double ?? 0.7
        self.bufferLength = defaults.object(forKey: SettingsKey.bufferLength.fullKey) as? Int ?? 500
    }
    
    // MARK: - UserDefaults Helpers
    
    private func save<T>(_ value: T, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.fullKey)
    }
    
    private func postNotification() {
        NotificationCenter.default.post(name: NSNotification.Name("AudioSettingsChanged"), object: nil)
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        playbackVolume = 0.7
        bufferLength = 500
        
        Logger.info("Audio settings reset to defaults")
    }
    
}
