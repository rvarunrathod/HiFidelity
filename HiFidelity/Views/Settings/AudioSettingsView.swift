//
//  AudioSettingsView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 15/11/25.
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Output Device// Output Device
            settingsSection(title: "Output Device", icon: "speaker.wave.3") {
                deviceSettings
            }
            
            Divider()

            // Audio Effects
            settingsSection(title: "Audio Effects", icon: "waveform.badge.magnifyingglass") {
                effectsSettings
            }
            
            Divider()
            
            // Audio Quality
            settingsSection(title: "Audio Quality", icon: "waveform") {
                qualitySettings
            }
            
            Divider()
            
            
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Settings Sections
    
    private var effectsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reverb Toggle
            settingRow(
                label: "Reverb",
                description: "Add spatial depth and ambience to audio"
            ) {
                Toggle("", isOn: Binding(
                    get: { effectsManager.isReverbEnabled },
                    set: { effectsManager.setReverbEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
            
            // Reverb Mix
            if effectsManager.isReverbEnabled {
            settingRow(
                    label: "Reverb Mix",
                    description: "Amount of reverb effect to apply"
            ) {
                HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(effectsManager.reverbMix) },
                            set: { effectsManager.setReverbMix(Float($0)) }
                        ), in: -96...0, step: 1)
                        .frame(width: 150)
                    
                        Text("\(Int(effectsManager.reverbMix)) dB")
                            .frame(width: 60, alignment: .trailing)
                        .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
    
    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Buffer Length
            settingRow(
                label: "Audio Buffer",
                description: "Larger buffer = more stable, but higher latency"
            ) {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(settings.bufferLength) },
                        set: { settings.bufferLength = Int($0) }
                    ), in: 100...2000, step: 100)
                    .frame(width: 150)
                    
                    Text("\(settings.bufferLength) ms")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Synchronize Sample Rate
            settingRow(
                label: "Synchronize Sample Rate with Music Player (Hog mode)",
                description: "Enable exclusive audio access for bit-perfect playback"
            ) {
                Toggle("", isOn: $settings.synchronizeSampleRate)
                    .toggleStyle(.switch)
            }
            
            // Info text when enabled
            if settings.synchronizeSampleRate {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    Text("When enabled, the app takes exclusive control (hog mode) of your audio device and automatically switches the device sample rate to match each track (44.1kHz, 48kHz, 96kHz, etc.) preventing BASS from resampling for true bit-perfect playback.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.headline)
            }
            
            content()
        }
    }
    
    private func settingRow<Content: View>(
        label: String,
        description: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            control()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AudioSettingsView()
        .frame(width: 700, height: 600)
}
