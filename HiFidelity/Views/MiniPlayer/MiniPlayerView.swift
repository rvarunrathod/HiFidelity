//
//  MiniPlayerView.swift
//  HiFidelity
//
//  Compact mini player window with integrated queue and lyrics
//

import SwiftUI
import AppKit

/// Compact mini player window view with expandable queue and lyrics
struct MiniPlayerView: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var database = DatabaseManager.shared
    
    @State private var expandedPanel: MiniPlayerPanel? = nil
    @State private var isHoveringArtwork = false
    @State private var showVolumePopover = false
    @AppStorage("miniPlayerShowArtwork") private var showArtwork = true
    @AppStorage("miniPlayerTransparent") private var isTransparent = true
    @AppStorage("miniPlayerFloatable") private var isFloatable = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Main compact player
            mainPlayerContent
            
            // Expanded panel (queue or lyrics)
            if let panel = expandedPanel {
                Divider()
                
                switch panel {
                case .queue:
                    MiniQueueView(onClose: { expandedPanel = nil })
                        .frame(height: 300)
                        
                case .lyrics:
                    MiniLyricsView(onClose: { expandedPanel = nil })
                        .frame(height: 300)
                }
            }
        }
        .frame(width: showArtwork ? 440 : 360)
        .background(
            Group {
                if isTransparent {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(8)
        .onChange(of: expandedPanel) { _, newPanel in
            updateWindowSize(expanded: newPanel != nil)
        }
        .onChange(of: showArtwork) { _, _ in
            updateWindowWidth()
        }
        .onChange(of: isFloatable) { _, _ in
            updateWindowLevel()
        }
    }
    
    // MARK: - Window Management
    
    private func updateWindowSize(expanded: Bool) {
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Player" }) else { return }
        
        let padding: CGFloat = 16  // 8px on each side
        let baseHeight: CGFloat = 140 + padding  // 140 (content height) + padding
        let expandedHeight: CGFloat = 300
        let targetHeight = expanded ? baseHeight + expandedHeight : baseHeight
        let targetWidth: CGFloat = (self.showArtwork ? 440 : 360) + padding
        
        // Update min/max size constraints immediately to prevent wobble
        window.minSize = NSSize(width: targetWidth, height: targetHeight)
        window.maxSize = NSSize(width: targetWidth, height: targetHeight)
        
        var frame = window.frame
        let oldHeight = frame.size.height
        let heightDiff = targetHeight - oldHeight
        
        // Keep the top position fixed, grow/shrink from bottom
        frame.size.height = targetHeight
        frame.size.width = targetWidth
        frame.origin.y -= heightDiff
        
        // Set frame without animation to prevent wobble
        window.setFrame(frame, display: true, animate: false)
        window.invalidateShadow()
    }
    
    private func updateWindowWidth() {
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Player" }) else { return }
        
        let padding: CGFloat = 16  // 8px on each side
        let targetWidth: CGFloat = (self.showArtwork ? 440 : 360) + padding
        let currentHeight = window.frame.size.height
        
        // Update min/max size constraints immediately
        window.minSize = NSSize(width: targetWidth, height: currentHeight)
        window.maxSize = NSSize(width: targetWidth, height: currentHeight)
        
        var frame = window.frame
        frame.size.width = targetWidth
        
        // Set frame without animation for instant response
        window.setFrame(frame, display: true, animate: false)
        window.invalidateShadow()
    }
    
    private func updateWindowLevel() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "Mini Player" }) else { return }
            
            window.level = self.isFloatable ? .floating : .normal
        }
    }
    
    // MARK: - Main Player Content
    
    private var mainPlayerContent: some View {
        Group {
            if let track = playback.currentTrack {
                playerWithTrack(track)
            } else {
                emptyPlayerState
            }
        }
    }
    
    private func playerWithTrack(_ track: Track) -> some View {
        // Main horizontal layout
        HStack(spacing: 0) {
            // Left: Album artwork (conditional)
            if showArtwork {
                artworkSection(track: track)
                Divider()
            }
            
            // Right: Controls
            controlsSection(track: track)
        }
        .frame(height: 140)
    }
    
    // MARK: - Track Info Header
    
    private func trackInfoHeader(track: Track) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if !track.album.isEmpty {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text(track.album)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Time display
            Text("-\(formatRemainingTime())")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            // Close button
            Button(action: {
                MiniPlayerWindowController.hide()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close Mini Player")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.05))
    }
    
    // MARK: - Artwork Section
    
    private func artworkSection(track: Track) -> some View {
        ZStack {
            TrackArtworkView(track: track, size: 140, cornerRadius: 0)
            
            // Play/Pause overlay on hover
            if isHoveringArtwork {
                Color.black.opacity(0.5)
                    .transition(.opacity)
                
                Button(action: {
                    playback.togglePlayPause()
                }) {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 10)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 140, height: 140)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringArtwork = hovering
            }
        }
    }
    
    // MARK: - Controls Section
    
    private func controlsSection(track: Track) -> some View {
        VStack(spacing: 12) {
            // Track info header
            trackInfoHeader(track: track)
            
            // Progress bar
            progressBar
            
            // Playback controls
            HStack(spacing: 0) {
                // Left: Volume
                volumeSection
                
                Spacer()
                
                // Center: Playback controls
                playbackButtons
                
                Spacer()
                
                // Right: Queue and Lyrics
                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)
                
                // Progress fill
                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: geometry.size.width * playback.progress, height: 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = value.location.x / geometry.size.width
                        playback.setProgress(max(0, min(1, progress)))
                    }
            )
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Volume Section
    
    private var volumeSection: some View {
        HStack(spacing: 8) {
            Button(action: {
                showVolumePopover.toggle()
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showVolumePopover, arrowEdge: .bottom) {
                VolumePopoverView()
                    .frame(width: 50, height: 140)
            }
            
            // More options menu
            Menu {
                // Show/Hide Artwork
                Button(action: {
                    showArtwork.toggle()
                }) {
                    HStack {
                        Text(showArtwork ? "Hide Artwork" : "Show Artwork")
                        Spacer()
                        if showArtwork {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // Transparent Background
                Button(action: {
                    isTransparent.toggle()
                }) {
                    HStack {
                        Text(isTransparent ? "Opaque Background" : "Transparent Background")
                        Spacer()
                        if isTransparent {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                // Float on Top
                Button(action: {
                    isFloatable.toggle()
                }) {
                    HStack {
                        Text("Float on Top")
                        Spacer()
                        if isFloatable {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Divider()
                
                // Shuffle
                Button(action: {
                    playback.toggleShuffle()
                }) {
                    HStack {
                        Label("Shuffle", systemImage: "shuffle")
                        Spacer()
                        if playback.isShuffleEnabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                
                // Repeat
                Button(action: {
                    playback.toggleRepeat()
                }) {
                    HStack {
                        Label("Repeat", systemImage: playback.repeatMode.iconName)
                        Spacer()
                        if playback.repeatMode != .off {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                // Favorite
                Button(action: {
                    playback.toggleFavorite()
                }) {
                    Label("Favorite", systemImage: isFavorite ? "heart.fill" : "heart")
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(playback.currentTrack == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(ButtonMenuStyle())
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Playback Buttons
    
    private var playbackButtons: some View {
        HStack(spacing: 16) {
            // Previous
            Button(action: {
                playback.previous()
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)
            
            // Play/Pause
            Button(action: {
                playback.togglePlayPause()
            }) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)
            
            // Next
            Button(action: {
                playback.next()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Lyrics button
            Button(action: {
                expandedPanel = expandedPanel == .lyrics ? nil : .lyrics
            }) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 16))
                    .foregroundColor(expandedPanel == .lyrics ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(expandedPanel == .lyrics ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Queue button
            Button(action: {
                expandedPanel = expandedPanel == .queue ? nil : .queue
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                        .foregroundColor(expandedPanel == .queue ? theme.currentTheme.primaryColor : .secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(expandedPanel == .queue ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    
                    if playback.queue.count > 0 {
                        Text("\(playback.queue.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyPlayerState: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("No Track Playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Close button
                Button(action: {
                    MiniPlayerWindowController.hide()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Close Mini Player")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.05))
            
            Divider()
            
            // Empty state content
            HStack(spacing: 0) {
                // Placeholder artwork (conditional)
                if showArtwork {
                    ZStack {
                        Rectangle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .frame(width: 140, height: 140)
                    
                    Divider()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Play a song to get started")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(.leading, 16)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 140)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatRemainingTime() -> String {
        let remaining = playback.duration - playback.currentTime
        let totalSeconds = Int(remaining)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
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
    
    private var isFavorite: Bool {
        guard let track = playback.currentTrack else { return false }
        return track.isFavorite
    }
}

// MARK: - Mini Player Panel Type

enum MiniPlayerPanel {
    case queue
    case lyrics
}

// MARK: - Visual Effect View (NSVisualEffectView wrapper)

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Volume Popover View

struct VolumePopoverView: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Volume percentage
            Text("\(Int(playback.volume * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            // Vertical volume slider
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Track background
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 4)
                    
                    // Volume fill
                    Capsule()
                        .fill(theme.currentTheme.primaryColor)
                        .frame(width: 4, height: geometry.size.height * playback.volume)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let height = geometry.size.height
                            let volume = 1 - (value.location.y / height)
                            playback.setVolume(max(0, min(1, volume)))
                            if playback.isMuted {
                                playback.toggleMute()
                            }
                        }
                )
            }
            
            // Volume icon at bottom
            Button(action: {
                playback.toggleMute()
            }) {
                Image(systemName: volumeIconForPopover)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
    }
    
    private var volumeIconForPopover: String {
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
}

// MARK: - Preview

#Preview {
    MiniPlayerView()
        .frame(width: 566, height: 208)
}

