//
//  PlaybackControlsCenter.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Central playback controls with play/pause, previous/next, shuffle, and repeat
struct PlaybackControlsCenter: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 8) {
            // Main control buttons
            controlButtons
            
            // Time display
            timeLabels
        }
        .fixedSize()
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        HStack(spacing: 16) {
            
            // Shuffle
            ControlButton(
                icon: "shuffle",
                size: 14,
                isActive: playback.isShuffleEnabled,
                isDisabled: false
            ) {
                playback.toggleShuffle()
            }
            
            // Previous
            ControlButton(
                icon: "backward.fill",
                size: 18,
                isActive: false,
                isDisabled: playback.currentTrack == nil
            ) {
                playback.previous()
            }
            
            // Play/Pause (larger, animated)
            PlayPauseButton(
                isPlaying: playback.isPlaying,
                isDisabled: playback.currentTrack == nil
            ) {
                playback.togglePlayPause()
            }
            
            // Next
            ControlButton(
                icon: "forward.fill",
                size: 18,
                isActive: false,
                isDisabled: playback.currentTrack == nil
            ) {
                playback.next()
            }
            
            // Repeat
            ControlButton(
                icon: playback.repeatMode.iconName,
                size: 14,
                isActive: playback.repeatMode != .off,
                isDisabled: false
            ) {
                playback.toggleRepeat()
            }
        }
    }
    
    // MARK: - Time Labels
    
    private var timeLabels: some View {
        HStack(spacing: 8) {
            Text(playback.formattedCurrentTime)
                .font(AppFonts.playbackTime)
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            Text("•")
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(playback.formattedDuration)
                .font(AppFonts.playbackTime)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Subcomponents

/// Generic control button for playback actions
private struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: size < 18 ? 28 : 32, height: size < 18 ? 28 : 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
        .disabled(isDisabled)
    }
    
    private var foregroundColor: Color {
        if isDisabled {
            return .secondary.opacity(0.3)
        }
        return isActive ? theme.currentTheme.primaryColor : .primary
    }
}

/// Large animated play/pause button
private struct PlayPauseButton: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(isDisabled ? .secondary.opacity(0.3) : theme.currentTheme.primaryColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainScaleButtonStyle())
        .disabled(isDisabled)
    }
}

/// Button style with scale animation
struct PlainScaleButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Preview

#Preview {
    PlaybackControlsCenter()
        .frame(width: 300, height: 100)
        .padding()
}

