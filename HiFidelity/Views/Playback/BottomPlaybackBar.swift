//
//  BottomPlaybackBar.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Bottom playback control bar with track info, controls, and volume
struct BottomPlaybackBar: View {
    @Binding var rightPanelTab: RightPanelTab
    @Binding var showRightPanel: Bool
    @Binding var showLeftSidebar: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressBarControl()
                .zIndex(1)
            
            // Main control bar
            HStack(spacing: 16) {
                // Left: Track Info
                TrackInfoDisplay()
                
                Spacer(minLength: 10)
                
                // Center: Playback Controls
                PlaybackControlsCenter()
                
                Spacer(minLength: 10)
                
                // Right: Volume and extras
                RightControlsSection(
                    rightPanelTab: $rightPanelTab,
                    showRightPanel: $showRightPanel
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(controlBarBackground)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }
    
    // MARK: - Background
    
    private var controlBarBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1),
                alignment: .top
            )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var rightPanelTab: RightPanelTab = .queue
        @State private var showRightPanel = true
        @State private var showLeftSidebar = true
        
        var body: some View {
    VStack {
        Spacer()
                BottomPlaybackBar(
                    rightPanelTab: $rightPanelTab,
                    showRightPanel: $showRightPanel,
                    showLeftSidebar: $showLeftSidebar
                )
    }
            .frame(width: 900, height: 300)
        }
    }
    
    return PreviewWrapper()
}

