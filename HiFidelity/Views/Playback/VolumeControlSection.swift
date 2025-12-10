//
//  VolumeControlSection.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Volume control with mute button and slider
struct VolumeControlSection: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 10) {
            // Mute button
            VolumeButton(
                icon: volumeIcon,
                action: { playback.toggleMute() }
            )
            
            // Volume slider
            Slider(
                value: volumeBinding,
                in: 0...1
            )
            .frame(width: 100)
            .accentColor(theme.currentTheme.primaryColor)
        }
    }
    
    private struct VolumeButton: View {
        let icon: String
        let action: () -> Void
        
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var volumeIcon: String {
        if playback.isMuted || playback.volume == 0 {
            return "speaker.slash.fill"
        } else if playback.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playback.volume < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { playback.isMuted ? 0 : playback.volume },
            set: { newValue in
                if playback.isMuted {
                    playback.toggleMute()
                }
                playback.setVolume(newValue)
            }
        )
    }
}

// MARK: - Preview

#Preview {
    VolumeControlSection()
        .frame(width: 150, height: 40)
        .padding()
}

