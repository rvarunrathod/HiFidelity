//
//  ProgressBarControl.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Interactive progress bar with scrubbing support
struct ProgressBarControl: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var tempProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: isHovering ? 4 : 2)
                    .fill(Color.secondary.opacity(isHovering ? 0.3 : 0.2))
                    .frame(height: isHovering ? 8 : 4)
                
                // Progress fill
                RoundedRectangle(cornerRadius: isHovering ? 4 : 2)
                    .fill(progressGradient)
                    .frame(
                        width: geometry.size.width * currentProgress,
                        height: isHovering ? 10 : 4
                    )
                
                // Scrubber handle
                if isHovering || isDragging {
                    scrubberHandle
                        .offset(x: geometry.size.width * currentProgress - 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        tempProgress = max(0, min(1, value.location.x / geometry.size.width))
                    }
                    .onEnded { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        playback.setProgress(progress)
                        isDragging = false
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // Tap is handled by drag gesture with minimumDistance: 0
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
        .frame(height: isHovering ? 10 : 4)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
    
    // MARK: - Subviews
    
    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.currentTheme.primaryColor,
                theme.currentTheme.primaryColor.opacity(0.8)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var scrubberHandle: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            Circle()
                .fill(theme.currentTheme.primaryColor)
                .frame(width: 12, height: 12)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
    }
    
    // MARK: - Computed Properties
    
    private var currentProgress: Double {
        isDragging ? tempProgress : playback.progress
    }
    
}

// MARK: - Preview

#Preview {
    VStack {
        ProgressBarControl()
            .frame(height: 10)
            .padding()
    }
    .frame(width: 600, height: 100)
}

