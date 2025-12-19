//
//  AudioEffectsManager.swift
//  HiFidelity
//
//  Manages DSP effects and custom processing for audio playback
//

import Foundation
import Bass
import Combine
import BassFX

/// Manages audio effects (DSP) for the current audio stream
/// Supports built-in BASS FX and custom DSP processing
class AudioEffectsManager: ObservableObject {
    static let shared = AudioEffectsManager()
    
    private let defaults = UserDefaults.standard
    private var isLoadingSettings = false
    
    // MARK: - Properties
    
    @Published var isEqualizerEnabled = false {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    // Equalizer bands (10-band graphic equalizer)
    // Frequencies: 32, 64, 125, 250, 500, 1K, 2K, 4K, 8K, 16K Hz
    @Published var equalizerBands: [Float] = Array(repeating: 0.0, count: 10) {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    @Published var preampGain: Double = 0.0 {
        didSet { 
            if !isLoadingSettings { 
                applyPreamp()
                saveSettings() 
            } 
        }
    }
    
    // Reverb settings
    @Published var isReverbEnabled = false {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    @Published var reverbMix: Float = -12.0 {
        didSet { if !isLoadingSettings { saveSettings() } }
    }
    
    // Custom preset management
    @Published var customPresets: [CustomEQPreset] = []
    
    // Current preset tracking
    @Published var currentPresetName: String = "Flat"
    @Published var currentPresetType: PresetType = .builtin
    
    // Effect handles (for removing effects later)
    private var activeEffects: [String: HFX] = [:]
    
    private var currentStream: HSTREAM = 0
    
    // Equalizer frequencies (Hz) - matching common EQ frequencies
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    
    // Settings keys
    enum SettingsKey: String, CaseIterable {
        case isEqualizerEnabled = "effects.equalizer.enabled"
        case equalizerBands = "effects.equalizer.bands"
        case preampGain = "effects.equalizer.preamp"
        case currentPresetName = "effects.equalizer.currentPresetName"
        case currentPresetType = "effects.equalizer.currentPresetType"
        case isReverbEnabled = "effects.reverb.enabled"
        case reverbMix = "effects.reverb.mix"
        case customPresets = "effects.equalizer.customPresets"
    }
    
    enum PresetType: String, Codable {
        case builtin
        case custom
        case userModified
    }
    
    // MARK: - Initialization
    
    private init() {
        Logger.info("AudioEffectsManager initialized")
        loadSettings()
    }
    
    // MARK: - Stream Management
    
    /// Update the current stream to apply effects to
    func setStream(_ stream: HSTREAM) {
        guard stream != currentStream else { return }
        
        Logger.debug("AudioEffectsManager: Setting new stream \(stream)")
        
        // Remove all effects from old stream
        removeAllEffects()
        
        // Update current stream
        currentStream = stream
        
        // Reapply enabled effects to new stream
        reapplyEffects()
    }
    
    /// Remove all effects (called when stream changes or is stopped)
    func clearStream() {
        removeAllEffects()
        currentStream = 0
    }
    
    // MARK: - Equalizer
    
    /// Enable/disable 10-band parametric equalizer
    func setEqualizerEnabled(_ enabled: Bool) {
        isEqualizerEnabled = enabled
        
        if enabled {
            applyEqualizer()
            applyPreamp()
        } else {
            removeEffect("equalizer")
            removeEffect("preamp")
        }
        
        Logger.info("Equalizer: \(enabled ? "Enabled" : "Disabled")")
    }
    
    /// Apply preamp gain to boost or reduce overall volume
    /// Preamp works independently of whether EQ bands are enabled
    func applyPreamp() {
        guard currentStream != 0 else { return }
        
        // Remove previous preamp FX
        removeEffect("preamp")
        
        // Skip if gain = 0 dB
        guard preampGain != 0 else { return }
        
        // Convert dB to linear: linear = pow(10, dB / 20)
        let linearGain = powf(10.0, Float(preampGain) / 20.0)
        
        // Add the BASS_FX volume effect (not DX8 effect)
        let fx = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_BFX_VOLUME), 0)
        
        if fx != 0 {
            // Use BASS_BFX_VOLUME structure from bass_fx.h
            var params = BASS_BFX_VOLUME()
            params.lChannel = Int32(BASS_BFX_CHANALL)  // Apply to all channels
            params.fVolume = linearGain                 // Linear volume multiplier
            
            // Apply parameters
            BASS_FXSetParameters(fx, &params)
            
            // Track it
            activeEffects["preamp"] = fx
            
            Logger.debug("Applied preamp \(preampGain) dB (linear=\(linearGain))")
        } else {
            Logger.error("Preamp failed. Error: \(BASS_ErrorGetCode())")
        }
    }
    
    
    /// Update equalizer band gain
    /// - Parameters:
    ///   - band: Band index (0-9)
    ///   - gain: Gain in dB (-15 to +15)
    func setEqualizerBand(_ band: Int, gain: Float) {
        guard band >= 0 && band < 10 else { return }
        
        equalizerBands[band] = gain
        
        // Mark as user-modified
        if currentPresetType != .userModified {
            currentPresetType = .userModified
            currentPresetName = "Custom"
        }
        
        if isEqualizerEnabled {
            updateSingleEQBand(band)
        }
    }
    
    /// Update a single EQ band (efficient - doesn't recreate entire EQ)
    private func updateSingleEQBand(_ band: Int) {
        guard currentStream != 0, let fxEQ = activeEffects["equalizer"] else { return }
        
        // Get current parameters for this band
        var params = BASS_BFX_PEAKEQ()
        params.lBand = Int32(band)
        BASS_FXGetParameters(fxEQ, &params)
        
        // Update only the gain
        params.fGain = equalizerBands[band]
        BASS_FXSetParameters(fxEQ, &params)
        
        Logger.debug("Updated EQ band \(band): \(equalizerBands[band]) dB")
    }
    
    /// Reset all equalizer bands to 0 dB
    func resetEqualizer() {
        equalizerBands = Array(repeating: 0.0, count: 10)
        preampGain = 0.0
        
        // Reset to Flat preset
        currentPresetName = "Flat"
        currentPresetType = .builtin
        
        if isEqualizerEnabled {
            applyEqualizer()
            applyPreamp()
        }
        
        Logger.info("Equalizer reset to flat (0 dB)")
    }
    
    /// Apply a built-in preset by name
    func applyBuiltinPreset(name: String, bands: [Float]) {
        isLoadingSettings = true
        
        equalizerBands = bands
        currentPresetName = name
        currentPresetType = .builtin
        
        isLoadingSettings = false
        
        if isEqualizerEnabled {
            applyEqualizer()
        }
        
        saveSettings()
        Logger.info("Applied built-in preset: \(name)")
    }
    
    // MARK: - Reverb
    
    /// Enable/disable reverb effect
    func setReverbEnabled(_ enabled: Bool) {
        isReverbEnabled = enabled
        
        if enabled {
            applyReverb()
        } else {
            removeEffect("reverb")
        }
        
        Logger.info("Reverb: \(enabled ? "Enabled" : "Disabled")")
    }
    
    /// Update reverb mix level
    /// - Parameter mix: Mix level in dB (-96 to 0, where -96 is none and 0 is max)
    func setReverbMix(_ mix: Float) {
        reverbMix = max(-96.0, min(0.0, mix))
        
        if isReverbEnabled {
            applyReverb()
        }
    }
    
    /// Apply reverb effect to current stream
    private func applyReverb() {
        guard currentStream != 0, isReverbEnabled else { return }
        
        // Remove existing reverb
        removeEffect("reverb")
        
        // Add reverb effect
        let fx = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_DX8_REVERB), 0)
        
        if fx != 0 {
            var params = BASS_DX8_REVERB()
            params.fInGain = 0.0                    // Input gain (dB)
            params.fReverbMix = reverbMix           // Reverb mix (-96 to 0 dB)
            params.fReverbTime = 1500.0             // Reverb time (ms)
            params.fHighFreqRTRatio = 0.5           // High-frequency RT ratio
            
            BASS_FXSetParameters(fx, &params)
            
            activeEffects["reverb"] = fx
            Logger.debug("Applied reverb: mix=\(reverbMix) dB")
        } else {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to apply reverb, error: \(errorCode)")
        }
    }
    
    func applyEqualizer() {
        guard currentStream != 0 else { return }
        
        // Remove existing EQ effect
        removeEffect("equalizer")
        
        // Create ONE peaking equalizer FX handle for all bands
        let fxEQ = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_BFX_PEAKEQ), 0)
        
        guard fxEQ != 0 else {
            let errorCode = BASS_ErrorGetCode()
            Logger.error("Failed to create equalizer FX: error \(errorCode)")
            return
        }
        
        // Set up all 10 bands using the same FX handle
        var params = BASS_BFX_PEAKEQ()
        params.fBandwidth = 1.0                         // Bandwidth in octaves
        params.fQ = 0.0                                 // Not used when bandwidth is set
        params.lChannel = Int32(BASS_BFX_CHANALL)       // Apply to all channels
        
        for (index, gain) in equalizerBands.enumerated() {
            params.lBand = Int32(index)                 // Band number
            params.fCenter = eqFrequencies[index]       // Center frequency in Hz
            params.fGain = gain                         // Gain in dB
            
            BASS_FXSetParameters(fxEQ, &params)
            Logger.debug("Set EQ band \(index): \(eqFrequencies[index]) Hz, \(gain) dB")
        }
        
        // Store the single FX handle
        activeEffects["equalizer"] = fxEQ
        Logger.debug("Applied equalizer with all bands: \(equalizerBands)")
    }
    
    
    // MARK: - Effect Management
    
    private func removeEffect(_ key: String) {
        // Remove specific effect
        if let fx = activeEffects[key] {
            BASS_ChannelRemoveFX(currentStream, fx)
            activeEffects.removeValue(forKey: key)
            Logger.debug("Removed effect: \(key)")
        }
    }
    
    private func removeAllEffects() {
        guard currentStream != 0 else {
            activeEffects.removeAll()
            return
        }
        
        for (key, fx) in activeEffects {
            BASS_ChannelRemoveFX(currentStream, fx)
            Logger.debug("Removed effect: \(key)")
        }
        
        activeEffects.removeAll()
    }
    
    private func reapplyEffects() {
        guard currentStream != 0 else { return }
        
        Logger.debug("Reapplying effects to new stream")
        
        if isEqualizerEnabled {
            applyEqualizer()
            applyPreamp()
        }
        
        if isReverbEnabled {
            applyReverb()
        }
    }
    
    // MARK: - Presets & Reset
    
    func disableEqualizer() {
        // Batch all changes to avoid multiple saves
        isLoadingSettings = true
        
        isEqualizerEnabled = false
        preampGain = 0.0
        equalizerBands = Array(repeating: 0.0, count: 10)
        
        isLoadingSettings = false
        
        removeAllEffects()
        saveSettings() // Single save after all changes
        
        Logger.info("Equalizer disabled and reset")
    }
    
    // MARK: - Persistence
    
    /// Load equalizer settings from UserDefaults
    private func loadSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        
        // Load equalizer state
        isEqualizerEnabled = defaults.bool(forKey: SettingsKey.isEqualizerEnabled.rawValue)
        
        // Load preamp gain
        preampGain = defaults.object(forKey: SettingsKey.preampGain.rawValue) as? Double ?? 0.0
        
        // Load equalizer bands
        if let savedBands = defaults.array(forKey: SettingsKey.equalizerBands.rawValue) as? [Float] {
            if savedBands.count == 10 {
                equalizerBands = savedBands
            }
        }
        
        // Load reverb settings
        isReverbEnabled = defaults.bool(forKey: SettingsKey.isReverbEnabled.rawValue)
        reverbMix = defaults.object(forKey: SettingsKey.reverbMix.rawValue) as? Float ?? -12.0
        
        // Load current preset info
        currentPresetName = defaults.string(forKey: SettingsKey.currentPresetName.rawValue) ?? "Flat"
        if let presetTypeString = defaults.string(forKey: SettingsKey.currentPresetType.rawValue),
           let presetType = PresetType(rawValue: presetTypeString) {
            currentPresetType = presetType
        } else {
            currentPresetType = .builtin
        }
        
        // Load custom presets
        if let presetsData = defaults.data(forKey: SettingsKey.customPresets.rawValue) {
            do {
                let decoder = JSONDecoder()
                customPresets = try decoder.decode([CustomEQPreset].self, from: presetsData)
            } catch {
                Logger.error("Failed to load custom presets: \(error)")
                customPresets = []
            }
        }
        
        Logger.info("Loaded audio effects settings from UserDefaults")
        Logger.debug("EQ Enabled: \(isEqualizerEnabled), Preset: \(currentPresetName) (\(currentPresetType.rawValue))")
        Logger.debug("Bands: \(equalizerBands), Preamp: \(preampGain) dB")
        Logger.debug("Reverb Enabled: \(isReverbEnabled), Mix: \(reverbMix) dB")
        Logger.debug("Custom Presets: \(customPresets.count)")
    }
    
    /// Save equalizer settings to UserDefaults
    private func saveSettings() {
        // Save equalizer state
        defaults.set(isEqualizerEnabled, forKey: SettingsKey.isEqualizerEnabled.rawValue)
        
        // Save preamp gain
        defaults.set(preampGain, forKey: SettingsKey.preampGain.rawValue)
        
        // Save equalizer bands
        defaults.set(equalizerBands, forKey: SettingsKey.equalizerBands.rawValue)
        
        // Save current preset info
        defaults.set(currentPresetName, forKey: SettingsKey.currentPresetName.rawValue)
        defaults.set(currentPresetType.rawValue, forKey: SettingsKey.currentPresetType.rawValue)
        
        // Save reverb settings
        defaults.set(isReverbEnabled, forKey: SettingsKey.isReverbEnabled.rawValue)
        defaults.set(reverbMix, forKey: SettingsKey.reverbMix.rawValue)
        
        // Save custom presets
        saveCustomPresets()
        
        Logger.debug("Saved audio effects settings to UserDefaults")
    }
    
    /// Save custom presets to UserDefaults
    private func saveCustomPresets() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(customPresets)
            defaults.set(data, forKey: SettingsKey.customPresets.rawValue)
            Logger.debug("Saved \(customPresets.count) custom presets")
        } catch {
            Logger.error("Failed to save custom presets: \(error)")
        }
    }
    
    /// Reset equalizer settings to defaults
    func resetAllSettings() {
        disableEqualizer()
        Logger.info("Reset equalizer settings to defaults")
    }
    
    // MARK: - Custom Preset Management
    
    /// Save current equalizer settings as a custom preset
    func saveCustomPreset(name: String) -> Bool {
        // Check if name already exists
        if customPresets.contains(where: { $0.name == name }) {
            Logger.warning("Custom preset '\(name)' already exists")
            return false
        }
        
        let preset = CustomEQPreset(
            id: UUID(),
            name: name,
            bandValues: equalizerBands,
            preampGain: Float(preampGain),
            dateCreated: Date()
        )
        
        customPresets.append(preset)
        saveCustomPresets()
        
        Logger.info("Saved custom preset: \(name)")
        return true
    }
    
    /// Load a custom preset
    func loadCustomPreset(_ preset: CustomEQPreset) {
        isLoadingSettings = true
        
        equalizerBands = preset.bandValues
        preampGain = Double(preset.preampGain)
        currentPresetName = preset.name
        currentPresetType = .custom
        
        isLoadingSettings = false
        
        if isEqualizerEnabled {
            applyEqualizer()
            applyPreamp()
        }
        
        saveSettings()
        Logger.info("Loaded custom preset: \(preset.name)")
    }
    
    /// Delete a custom preset
    func deleteCustomPreset(_ preset: CustomEQPreset) {
        customPresets.removeAll { $0.id == preset.id }
        saveCustomPresets()
        Logger.info("Deleted custom preset: \(preset.name)")
    }
    
    /// Rename a custom preset
    func renameCustomPreset(_ preset: CustomEQPreset, newName: String) -> Bool {
        // Check if new name already exists
        if customPresets.contains(where: { $0.name == newName && $0.id != preset.id }) {
            Logger.warning("Custom preset '\(newName)' already exists")
            return false
        }
        
        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index].name = newName
            saveCustomPresets()
            Logger.info("Renamed preset to: \(newName)")
            return true
        }
        
        return false
    }
    
    /// Export preset to JSON
    func exportPreset(_ preset: CustomEQPreset) -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preset)
            return String(data: data, encoding: .utf8)
        } catch {
            Logger.error("Failed to export preset: \(error)")
            return nil
        }
    }
    
    /// Import preset from JSON
    func importPreset(from jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else {
            Logger.error("Invalid JSON string")
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            var preset = try decoder.decode(CustomEQPreset.self, from: data)
            
            // Generate new ID and update date
            preset.id = UUID()
            preset.dateCreated = Date()
            
            // Make name unique if needed
            var uniqueName = preset.name
            var counter = 1
            while customPresets.contains(where: { $0.name == uniqueName }) {
                uniqueName = "\(preset.name) (\(counter))"
                counter += 1
            }
            preset.name = uniqueName
            
            customPresets.append(preset)
            saveCustomPresets()
            
            Logger.info("Imported custom preset: \(preset.name)")
            return true
        } catch {
            Logger.error("Failed to import preset: \(error)")
            return false
        }
    }
}

// MARK: - Custom EQ Preset Model

struct CustomEQPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var bandValues: [Float]  // 10 band values
    var preampGain: Float
    var dateCreated: Date
    
    static func == (lhs: CustomEQPreset, rhs: CustomEQPreset) -> Bool {
        return lhs.id == rhs.id
    }
}
