//
//  AudioDeviceSelector.swift
//  HiFidelity
//
//  Audio output device selector for bottom playback bar
//

import SwiftUI

/// Audio device selector button with popover menu
struct AudioDeviceSelector: View {
    @ObservedObject var dacManager = DACManager.shared
    @ObservedObject var theme = AppTheme.shared
    @State private var showDeviceMenu = false
    
    var body: some View {
        Button(action: {
            showDeviceMenu.toggle()
            dacManager.refreshDeviceList()
        }) {
            Image(systemName: "hifispeaker")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
        .popover(isPresented: $showDeviceMenu, arrowEdge: .top) {
            deviceMenuContent
        }
        .help("Select Audio Output Device")
    }
    
    // MARK: - Device Menu Content
    
    private var deviceMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "hifispeaker")
                    .foregroundColor(theme.currentTheme.primaryColor)
                Text("Audio Output Device")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Device list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if dacManager.availableDevices.isEmpty {
                        Text("No output devices found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(dacManager.availableDevices) { device in
                            deviceRow(device)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Footer info
            if let currentDevice = dacManager.currentDevice {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("\(Int(currentDevice.sampleRate)) Hz • \(channelDescription(currentDevice.channels))")
                        .font(.system(size: 11))
                    
                    if AudioSettings.shared.synchronizeSampleRate {
                        Text("• Sync Mode")
                            .font(.system(size: 11))
                            .foregroundColor(theme.currentTheme.primaryColor)
                    }
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Device Row
    
    private func deviceRow(_ device: AudioOutputDevice) -> some View {
        Button(action: {
            selectDevice(device)
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isCurrentDevice(device) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isCurrentDevice(device) ? theme.currentTheme.primaryColor : .secondary.opacity(0.3))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        Text("\(Int(device.sampleRate)) Hz")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text(channelDescription(device.channels))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            isCurrentDevice(device) ? 
                Color.accentColor.opacity(0.1) : 
                Color.clear
        )
        .onHover { hovering in
            if hovering && !isCurrentDevice(device) {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectDevice(_ device: AudioOutputDevice) {
        guard !isCurrentDevice(device) else { return }
        
        if dacManager.switchToDevice(device) {
            Logger.info("Switched to device: \(device.name)")
            showDeviceMenu = false
            
            
        }
    }
    
    private func isCurrentDevice(_ device: AudioOutputDevice) -> Bool {
        device.id == dacManager.currentDeviceID
    }
    
    private func channelDescription(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 4: return "4.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels)ch"
        }
    }
}



// MARK: - Preview

#Preview {
    AudioDeviceSelector()
        .padding()
        .frame(width: 400, height: 200)
}

