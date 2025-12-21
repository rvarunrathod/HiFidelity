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
            ZStack {
                // Centered playback controls
                PlaybackControlsCenter()
                
                // Left and right sections
                HStack(spacing: 8) {
                    // Left: Track Info
                    TrackInfoDisplay()
                    
                    Spacer()
                    
                    // Right: Volume and extras
                    RightControlsSection(
                        rightPanelTab: $rightPanelTab,
                        showRightPanel: $showRightPanel
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(controlBarBackground)
            .contentShape(Rectangle()) // Make entire area tappable
            .onTapGesture {
                // Dismiss focus from search and tables when clicking on player
                NotificationCenter.default.post(name: .dismissAllFocus, object: nil)
            }
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

