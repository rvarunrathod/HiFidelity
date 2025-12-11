//
//  MiniQueueView.swift
//  HiFidelity
//
//  Compact queue view for mini player
//

import SwiftUI

/// Compact queue view for mini player window
struct MiniQueueView: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    @State private var hoveredIndex: Int? = nil
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Queue content
            if playback.queue.isEmpty && playback.currentTrack == nil {
                emptyState
            } else {
                queueList
            }
        }
        .background(Color.black.opacity(0.05))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Queue")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            if !playback.queue.isEmpty {
                Text("(\(playback.queue.count))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Autoplay toggle
            if !playback.queue.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: playback.isAutoplayEnabled ? "infinity.circle.fill" : "infinity.circle")
                        .font(.system(size: 14))
                        .foregroundColor(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor : .secondary)
                    
                    Text("Autoplay")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(playback.isAutoplayEnabled ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                )
                .onTapGesture {
                    playback.isAutoplayEnabled.toggle()
                }
            }
            
            // Clear queue button
            if !playback.queue.isEmpty {
                Button(action: {
                    playback.clearQueue()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Queue List
    
    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Current track (if playing)
                if let currentTrack = playback.currentTrack {
                    currentTrackRow(track: currentTrack)
                    
                    if !playback.queue.isEmpty {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                
                // Queue items
                ForEach(Array(playback.queue.enumerated()), id: \.offset) { index, track in
                    queueItem(track: track, index: index)
                        .background(
                            hoveredIndex == index ?
                                Color.white.opacity(0.08) :
                                Color.clear
                        )
                        .onHover { hovering in
                            hoveredIndex = hovering ? index : nil
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func currentTrackRow(track: Track) -> some View {
        HStack(spacing: 10) {
            // Playing indicator
            ZStack {
                TrackArtworkView(track: track, size: 40, cornerRadius: 4)
                
                // Animated playing indicator overlay
                if playback.isPlaying {
                    Color.black.opacity(0.5)
                        .cornerRadius(4)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(theme.currentTheme.primaryColor)
                                .frame(width: 2, height: CGFloat.random(in: 6...14))
                                .animation(
                                    .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                    value: playback.isPlaying
                                )
                        }
                    }
                }
            }
            .frame(width: 40, height: 40)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundColor(theme.currentTheme.primaryColor)
                    
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.currentTheme.primaryColor)
                        .lineLimit(1)
                }
                
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.currentTheme.primaryColor.opacity(0.1))
    }
    
    private func queueItem(track: Track, index: Int) -> some View {
        HStack(spacing: 10) {
            // Position number
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 20)
            
            // Album artwork
            TrackArtworkView(track: track, size: 40, cornerRadius: 3)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            // Actions on hover
            if hoveredIndex == index {
                Button(action: {
                    playback.removeFromQueue(at: index)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            } else {
                Text(track.formattedDuration)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            playback.play(track: track)
        }
        .contextMenu {
            Button("Play Now") {
                playback.play(track: track)
            }
            
            Button("Remove from Queue") {
                playback.removeFromQueue(at: index)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("Queue is empty")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    MiniQueueView(onClose: {})
        .frame(width: 550, height: 300)
}

