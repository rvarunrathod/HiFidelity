//
//  TrackInfoDisplay.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Display current playing track information with artwork and favorite button
struct TrackInfoDisplay: View {
    @ObservedObject var playback = PlaybackController.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 14) {
            // Album artwork
            artworkView
            
            // Track details and favorite
            if let track = playback.currentTrack {
                trackDetails(for: track)
                favoriteButton(for: track)
            } else {
                placeholderDetails
            }
        }
        .frame(minWidth: 200, maxWidth: 300, alignment: .leading)
    }
    
    // MARK: - Artwork View
    
    @ViewBuilder
    private var artworkView: some View {
        if let track = playback.currentTrack {
            TrackArtworkView(track: track, size: 56, cornerRadius: 6)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        } else {
            placeholderArtwork
        }
    }
    
    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
    
    // MARK: - Track Details
    
    private func trackDetails(for track: Track) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(track.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            Text(track.artist)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.secondary.opacity(0.85))
        }
    }
    
    private var placeholderDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Not Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
            
            Text("Select a track to play")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
    
    // MARK: - Favorite Button
    
    private func favoriteButton(for track: Track) -> some View {
        FavoriteButton(
            isFavorite: track.isFavorite,
            action: { playback.toggleFavorite() }
        )
    }
    
    private struct FavoriteButton: View {
        let isFavorite: Bool
        let action: () -> Void
        
        @ObservedObject var theme = AppTheme.shared
        @State private var isHovered = false
        
        var body: some View {
            Button(action: action) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isFavorite ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }
}

// MARK: - Preview

#Preview {
    TrackInfoDisplay()
        .frame(width: 320, height: 80)
        .padding()
}

