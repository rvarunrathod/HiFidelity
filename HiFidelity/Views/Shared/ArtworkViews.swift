//
//  ArtworkViews.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import SwiftUI
import AppKit

// MARK: - Track Artwork View

/// High-performance SwiftUI view for displaying track artwork
/// Features: async loading, caching, task cancellation, equatable optimization
struct TrackArtworkView: View, Equatable {
    let track: Track
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(track: Track, size: CGFloat = 40, cornerRadius: CGFloat = 4) {
        self.track = track
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    static func == (lhs: TrackArtworkView, rhs: TrackArtworkView) -> Bool {
        lhs.track.trackId == rhs.track.trackId &&
        lhs.size == rhs.size &&
        lhs.cornerRadius == rhs.cornerRadius
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: track.trackId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
    
    private func loadArtwork() async {
        guard let trackId = track.trackId else {
            artwork = nil
            return
        }
        
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedArtwork(for: trackId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            
            await withCheckedContinuation { continuation in
                ArtworkCache.shared.getArtwork(for: trackId, size: size) { image in
                    Task { @MainActor in
                        guard !Task.isCancelled,
                              self.track.trackId == trackId else {
                            continuation.resume()
                            return
                        }
                        self.artwork = image
                        continuation.resume()
                    }
                }
            }
        }
        
        await loadTask?.value
    }
}

// MARK: - Album Artwork View

/// High-performance SwiftUI view for displaying album artwork
/// Features: async loading, caching, task cancellation, gradient placeholder
struct AlbumArtworkView: View, Equatable {
    let albumId: Int64
    let size: CGFloat
    let cornerRadius: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(albumId: Int64, size: CGFloat = 160, cornerRadius: CGFloat = 8) {
        self.albumId = albumId
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    static func == (lhs: AlbumArtworkView, rhs: AlbumArtworkView) -> Bool {
        lhs.albumId == rhs.albumId &&
        lhs.size == rhs.size &&
        lhs.cornerRadius == rhs.cornerRadius
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: albumId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundColor(.white)
        }
    }
    
    private func loadArtwork() async {
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedAlbumArtwork(for: albumId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            
            await withCheckedContinuation { continuation in
                ArtworkCache.shared.getAlbumArtwork(for: albumId, size: size) { image in
                    Task { @MainActor in
                        guard !Task.isCancelled else {
                            continuation.resume()
                            return
                        }
                        self.artwork = image
                        continuation.resume()
                    }
                }
            }
        }
        
        await loadTask?.value
    }
}

// MARK: - Artist Artwork View

/// High-performance SwiftUI view for displaying artist artwork (circular)
/// Features: async loading, caching, task cancellation, circular clipping
struct ArtistArtworkView: View, Equatable {
    let artistId: Int64
    let size: CGFloat
    
    @State private var artwork: NSImage?
    @State private var loadTask: Task<Void, Never>?
    
    init(artistId: Int64, size: CGFloat = 160) {
        self.artistId = artistId
        self.size = size
    }
    
    static func == (lhs: ArtistArtworkView, rhs: ArtistArtworkView) -> Bool {
        lhs.artistId == rhs.artistId &&
        lhs.size == rhs.size
    }
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: artistId) {
            await loadArtwork()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundColor(.white)
        }
    }
    
    private func loadArtwork() async {
        // Quick synchronous cache check
        if let cached = ArtworkCache.shared.getCachedArtistArtwork(for: artistId, size: size) {
            artwork = cached
            return
        }
        
        // Load asynchronously
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            
            await withCheckedContinuation { continuation in
                ArtworkCache.shared.getArtistArtwork(for: artistId, size: size) { image in
                    Task { @MainActor in
                        guard !Task.isCancelled else {
                            continuation.resume()
                            return
                        }
                        self.artwork = image
                        continuation.resume()
                    }
                }
            }
        }
        
        await loadTask?.value
    }
}

