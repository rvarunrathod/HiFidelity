//
//  RightControlsSection.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Right side controls including queue, lyrics buttons, and volume
struct RightControlsSection: View {
    @Binding var rightPanelTab: RightPanelTab
    @Binding var showRightPanel: Bool
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Queue button
            PanelToggleButton(
                icon: "list.bullet",
                panelTab: .queue,
                currentTab: rightPanelTab,
                isShowing: showRightPanel
            ) {
                togglePanel(to: .queue)
            }
            
            // Lyrics button
            PanelToggleButton(
                icon: "quote.bubble",
                panelTab: .lyrics,
                currentTab: rightPanelTab,
                isShowing: showRightPanel
            ) {
                togglePanel(to: .lyrics)
            }
            
            Divider()
                .frame(height: 24)

            HStack(spacing: 2) {
                // Equalizer
                EqualizerButton()

                // Sample rate sync button
                SampleRateSyncButton()

                // Audio device selector
                AudioDeviceSelector()
                
                // Volume control
                VolumeControlSection()
            }
        }
        .frame(width: 420, alignment: .trailing)
    }
    
    // MARK: - Actions
    
    private func togglePanel(to tab: RightPanelTab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !showRightPanel || rightPanelTab != tab {
                showRightPanel = true
                rightPanelTab = tab
            } else {
                showRightPanel = false
            }
        }
    }
}

// MARK: - Subcomponents

/// Button to toggle right panel tabs
private struct PanelToggleButton: View {
    let icon: String
    let panelTab: RightPanelTab
    let currentTab: RightPanelTab
    let isShowing: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isActive ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
    }
    
    private var isActive: Bool {
        isShowing && currentTab == panelTab
    }
}


// MARK: - Equalizer Button

/// Button to open the audio effects window
struct EqualizerButton: View {
    @ObservedObject var theme = AppTheme.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button(action: {
            openWindow(id: "audio-effects")
        }) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
        .help("Audio Effects & Equalizer")
    }
}

// MARK: - Sample Rate Sync Button

/// Button to toggle sample rate synchronization (hog mode)
struct SampleRateSyncButton: View {
    @ObservedObject var settings = AudioSettings.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button(action: {
            settings.synchronizeSampleRate.toggle()
        }) {
            Image(systemName: settings.synchronizeSampleRate ? "lock.fill" : "lock")
                .font(.system(size: 16))
                .foregroundColor(settings.synchronizeSampleRate ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainHoverButtonStyle())
        .help(settings.synchronizeSampleRate ? "Disable Bit-Perfect Playback (Hog Mode Active)" : "Enable Bit-Perfect Playback (Hog Mode Active)")
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var rightPanelTab: RightPanelTab = .queue
        @State private var showRightPanel = true
        
        var body: some View {
            RightControlsSection(
                rightPanelTab: $rightPanelTab,
                showRightPanel: $showRightPanel
            )
            .frame(width: 340, height: 60)
            .padding()
        }
    }
    
    return PreviewWrapper()
}
