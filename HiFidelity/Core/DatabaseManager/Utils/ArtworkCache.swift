//
//  ArtworkCache.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import Foundation
import AppKit
import GRDB

// MARK: - Artwork Cache

/// High-performance artwork cache with downsampling, prefetching, and multi-level caching
/// 
/// Features:
/// - Two-tier memory cache (thumbnails + full-size)
/// - Size-specific downsampling for optimal memory usage
/// - In-flight request deduplication
/// - Fallback chain: album → track → nil
/// - Cross-caching (album artwork shared across tracks)
final class ArtworkCache {
    
    // MARK: - Singleton
    
    static let shared = ArtworkCache()
    
    // MARK: - Properties
    
    // Two-tier cache system optimized for different use cases
    private let thumbnailCache = NSCache<NSString, NSImage>()  // For lists/grids (≤200pt)
    private let fullSizeCache = NSCache<NSString, NSImage>()   // For detail views (>200pt)
    
    // Tracks entities known to have no artwork (avoid repeated DB queries)
    private let noArtworkSet = NSMutableSet()
    private let noArtworkQueue = DispatchQueue(label: "com.hifidelity.noArtworkSet", attributes: .concurrent)
    
    // Processing queues
    private let decodingQueue = DispatchQueue(label: "com.hifidelity.imageDecoding", qos: .userInitiated, attributes: .concurrent)
    private let dbQueue = DispatchQueue(label: "com.hifidelity.artworkCache", qos: .userInitiated)
    
    // In-flight request tracking (prevent duplicate loads)
    private var inflightRequests = Set<String>()
    private let inflightQueue = DispatchQueue(label: "com.hifidelity.inflightRequests")
    
    // MARK: - Initialization
    
    private init() {
        let userCacheSizeMB = UserDefaults.standard.object(forKey: "artworkCacheSize") as? Int ?? 500
        configureCacheSize(sizeMB: userCacheSizeMB)
    }
    
    // MARK: - Configuration
    
    /// Update cache size limits dynamically
    /// - Parameter sizeMB: Total cache size in megabytes (minimum 100 MB)
    func updateCacheSize(sizeMB: Int) {
        let safeSizeMB = max(100, sizeMB)
        UserDefaults.standard.set(safeSizeMB, forKey: "artworkCacheSize")
        configureCacheSize(sizeMB: safeSizeMB)
        Logger.info("Updated artwork cache size to \(safeSizeMB) MB")
    }
    
    private func configureCacheSize(sizeMB: Int) {
        let totalBytes = sizeMB * 1024 * 1024
        
        // Split allocation: 40% thumbnails (high volume), 60% full-size (lower volume)
        let thumbnailBytes = Int(Double(totalBytes) * 0.4)
        let fullSizeBytes = Int(Double(totalBytes) * 0.6)
        
        thumbnailCache.countLimit = sizeMB * 2
        thumbnailCache.totalCostLimit = thumbnailBytes
        thumbnailCache.name = "ArtworkThumbnailCache"
        
        fullSizeCache.countLimit = sizeMB / 2
        fullSizeCache.totalCostLimit = fullSizeBytes
        fullSizeCache.name = "ArtworkFullSizeCache"
    }
    
    
    
    // MARK: - Public API - Async Artwork Loading
    
    /// Get artwork for a track with fallback chain: album → track → nil
    /// - Parameters:
    ///   - trackId: Track database ID
    ///   - size: Target size in points (automatically handles Retina scaling)
    ///   - completion: Called on main thread with result
    func getArtwork(for trackId: Int64, size: CGFloat = 40, completion: @escaping (NSImage?) -> Void) {
        let trackKey = "track_\(trackId)_\(Int(size))" as NSString
        let cache = size <= 200 ? thumbnailCache : fullSizeCache
        
        // Check appropriate cache first (extremely fast, thread-safe)
        if let cachedImage = cache.object(forKey: trackKey) {
            completion(cachedImage)
            return
        }
        
        // OPTIMIZATION: Check if we can get albumId from DatabaseCache
        if let cachedTrack = DatabaseCache.shared.track(trackId),
           let albumId = cachedTrack.albumId {
            let albumKey = "album_\(albumId)_\(Int(size))" as NSString
            if let albumArtwork = cache.object(forKey: albumKey) {
                // Found album artwork in cache! Use it for this track too
                let cost = calculateImageCost(albumArtwork)
                cache.setObject(albumArtwork, forKey: trackKey, cost: cost)
                completion(albumArtwork)
                return
            }
        }
        
        // Thread-safe check if we know this track has no artwork
        let noArtworkKey = "track_\(trackId)" as NSString
        var hasNoArtwork = false
        noArtworkQueue.sync {
            hasNoArtwork = noArtworkSet.contains(noArtworkKey)
        }
        
        if hasNoArtwork {
            completion(nil)
            return
        }
        
        // Check if already loading this image
        let requestKey = "track_\(trackId)_\(Int(size))"
        var isInflight = false
        inflightQueue.sync {
            isInflight = inflightRequests.contains(requestKey)
            if !isInflight {
                inflightRequests.insert(requestKey)
            }
        }
        
        if isInflight {
            // Already loading, just wait and check cache again shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if let cached = self?.cache(for: size).object(forKey: trackKey) {
                    completion(cached)
                } else {
                    completion(nil)
                }
            }
            return
        }
        
        // Load from database on background queue
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                _ = self.inflightQueue.sync {
                    self.inflightRequests.remove(requestKey)
                }
            }
            
            // Double-check cache
            if let cachedImage = cache.object(forKey: trackKey) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }
            
            // Load and decode artwork
            do {
                guard let result = try self.loadTrackArtworkWithFallback(trackId: trackId) else {
                    // Track exists but has no artwork
                    self.noArtworkQueue.async(flags: .barrier) {
                        self.noArtworkSet.add(noArtworkKey)
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Decode and downsample image OFF main thread
                self.decodingQueue.async {
                    guard let image = self.downsampleImage(data: result.data, targetSize: size) else {
                        self.noArtworkQueue.async(flags: .barrier) {
                            self.noArtworkSet.add(noArtworkKey)
                        }
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Cache the downsampled image
                    let cost = self.calculateImageCost(image)
                    cache.setObject(image, forKey: trackKey, cost: cost)
                
                // OPTIMIZATION: If artwork came from album, also cache under album key
                if let albumId = result.albumId {
                        let albumKey = "album_\(albumId)_\(Int(size))" as NSString
                        cache.setObject(image, forKey: albumKey, cost: cost)
                }
                
                // Return on main thread
                DispatchQueue.main.async {
                    completion(image)
                    }
                }
            } catch {
                Logger.warning("Failed to load artwork for track \(trackId): \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    /// Get artwork for an album
    /// - Parameters:
    ///   - albumId: Album database ID
    ///   - size: Target size in points
    ///   - completion: Called on main thread with result
    func getAlbumArtwork(for albumId: Int64, size: CGFloat = 160, completion: @escaping (NSImage?) -> Void) {
        loadArtwork(
            entityType: .album,
            entityId: albumId,
            size: size,
            completion: completion
        )
    }
    
    /// Get artwork for an artist
    /// - Parameters:
    ///   - artistId: Artist database ID
    ///   - size: Target size in points
    ///   - completion: Called on main thread with result
    func getArtistArtwork(for artistId: Int64, size: CGFloat = 160, completion: @escaping (NSImage?) -> Void) {
        loadArtwork(
            entityType: .artist,
            entityId: artistId,
            size: size,
            completion: completion
        )
    }
    
    // MARK: - Public API - Synchronous Cache Access
    
    /// Get cached artwork for track (returns immediately, nil if not cached)
    func getCachedArtwork(for trackId: Int64, size: CGFloat = 40) -> NSImage? {
        getCachedImage(entityType: .track, entityId: trackId, size: size)
    }
    
    /// Get cached artwork for album (returns immediately, nil if not cached)
    func getCachedAlbumArtwork(for albumId: Int64, size: CGFloat = 160) -> NSImage? {
        getCachedImage(entityType: .album, entityId: albumId, size: size)
    }
    
    /// Get cached artwork for artist (returns immediately, nil if not cached)
    func getCachedArtistArtwork(for artistId: Int64, size: CGFloat = 160) -> NSImage? {
        getCachedImage(entityType: .artist, entityId: artistId, size: size)
    }
    
    // MARK: - Public API - Preloading
    
    /// Preload artwork for visible tracks (call before scrolling into view)
    /// - Parameters:
    ///   - trackIds: Track IDs to preload
    ///   - size: Target size
    ///   - maxConcurrent: Limit to prevent system overload (default: 10)
    func preloadArtwork(for trackIds: [Int64], size: CGFloat = 40, maxConcurrent: Int = 10) {
        preloadImages(entityType: .track, entityIds: trackIds, size: size, maxConcurrent: maxConcurrent)
    }
    
    /// Preload artwork for albums (call before scrolling into view)
    func preloadAlbumArtwork(for albumIds: [Int64], size: CGFloat = 160, maxConcurrent: Int = 10) {
        preloadImages(entityType: .album, entityIds: albumIds, size: size, maxConcurrent: maxConcurrent)
    }
    
    // MARK: - Public API - Cache Invalidation
    
    /// Invalidate track artwork (call when artwork updated)
    func invalidate(trackId: Int64) {
        invalidateCache(entityType: .track, entityId: trackId)
    }
    
    /// Invalidate album artwork (call when artwork updated)
    func invalidateAlbum(albumId: Int64) {
        invalidateCache(entityType: .album, entityId: albumId)
    }
    
    /// Invalidate artist artwork (call when artwork updated)
    func invalidateArtist(artistId: Int64) {
        invalidateCache(entityType: .artist, entityId: artistId)
    }
    
    /// Clear all cached artwork
    func clearAll() {
        thumbnailCache.removeAllObjects()
        fullSizeCache.removeAllObjects()
        
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.removeAllObjects()
        }
        
        inflightQueue.sync {
            inflightRequests.removeAll()
        }
        
        Logger.info("Cleared all artwork cache")
    }
    
    // MARK: - Private Types
    
    /// Entity types that can have artwork
    private enum EntityType: String {
        case track
        case album
        case artist
    }
    
    // MARK: - Private Generic Helpers
    
    /// Generic artwork loading for any entity type
    private func loadArtwork(
        entityType: EntityType,
        entityId: Int64,
        size: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        let key = cacheKey(entityType: entityType, entityId: entityId, size: size)
        let cache = cache(for: size)
        
        // Fast path: Check cache first
        if let cachedImage = cache.object(forKey: key) {
            completion(cachedImage)
            return
        }
        
        // Check if known to have no artwork
        if isKnownNoArtwork(entityType: entityType, entityId: entityId) {
            completion(nil)
            return
        }
        
        // Check if already loading (prevent duplicate requests)
        let requestKey = requestKey(entityType: entityType, entityId: entityId, size: size)
        if isInflightRequest(requestKey) {
            // Wait briefly and check cache again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                completion(self?.cache(for: size).object(forKey: key))
            }
            return
        }
        
        // Mark as in-flight
        markInflightRequest(requestKey, inflight: true)
        
        // Load from database on background queue
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            defer {
                self.markInflightRequest(requestKey, inflight: false)
            }
            
            // Double-check cache
            if let cachedImage = cache.object(forKey: key) {
                DispatchQueue.main.async {
                    completion(cachedImage)
                }
                return
            }
            
            // Load artwork data from database
            self.loadArtworkData(entityType: entityType, entityId: entityId) { result in
                guard let artworkData = result else {
                    self.markNoArtwork(entityType: entityType, entityId: entityId)
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // Decode and downsample OFF main thread
                self.decodingQueue.async {
                    guard let image = self.downsampleImage(data: artworkData, targetSize: size) else {
                        self.markNoArtwork(entityType: entityType, entityId: entityId)
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                        return
                    }
                    
                    // Cache the image
                    let cost = self.calculateImageCost(image)
                    cache.setObject(image, forKey: key, cost: cost)
                    
                    DispatchQueue.main.async {
                        completion(image)
                    }
                }
            }
        }
    }
    
    /// Get cached image synchronously
    private func getCachedImage(entityType: EntityType, entityId: Int64, size: CGFloat) -> NSImage? {
        let key = cacheKey(entityType: entityType, entityId: entityId, size: size)
        let cache = cache(for: size)
        return cache.object(forKey: key)
    }
    
    /// Preload multiple images
    private func preloadImages(
        entityType: EntityType,
        entityIds: [Int64],
        size: CGFloat,
        maxConcurrent: Int
    ) {
        let uncached = entityIds.filter { entityId in
            getCachedImage(entityType: entityType, entityId: entityId, size: size) == nil &&
            !isKnownNoArtwork(entityType: entityType, entityId: entityId)
        }
        
        let limited = Array(uncached.prefix(maxConcurrent))
        
        for entityId in limited {
            loadArtwork(entityType: entityType, entityId: entityId, size: size) { _ in }
        }
    }
    
    /// Invalidate cached artwork for an entity
    private func invalidateCache(entityType: EntityType, entityId: Int64) {
        let standardSizes: [Int] = [40, 56, 140, 160, 200, 300]
        
        for size in standardSizes {
            let key = cacheKey(entityType: entityType, entityId: entityId, size: CGFloat(size))
            thumbnailCache.removeObject(forKey: key)
            fullSizeCache.removeObject(forKey: key)
        }
        
        let noArtworkKey = noArtworkKey(entityType: entityType, entityId: entityId)
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.remove(noArtworkKey)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Get the appropriate cache for a given size
    private func cache(for size: CGFloat) -> NSCache<NSString, NSImage> {
        size <= 200 ? thumbnailCache : fullSizeCache
    }
    
    /// Generate cache key for an entity
    private func cacheKey(entityType: EntityType, entityId: Int64, size: CGFloat) -> NSString {
        "\(entityType.rawValue)_\(entityId)_\(Int(size))" as NSString
    }
    
    /// Generate no-artwork key for an entity
    private func noArtworkKey(entityType: EntityType, entityId: Int64) -> NSString {
        "\(entityType.rawValue)_\(entityId)" as NSString
    }
    
    /// Generate request key for in-flight tracking
    private func requestKey(entityType: EntityType, entityId: Int64, size: CGFloat) -> String {
        "\(entityType.rawValue)_\(entityId)_\(Int(size))"
    }
    
    /// Check if entity is known to have no artwork
    private func isKnownNoArtwork(entityType: EntityType, entityId: Int64) -> Bool {
        let key = noArtworkKey(entityType: entityType, entityId: entityId)
        return noArtworkQueue.sync {
            noArtworkSet.contains(key)
        }
    }
    
    /// Mark entity as having no artwork
    private func markNoArtwork(entityType: EntityType, entityId: Int64) {
        let key = noArtworkKey(entityType: entityType, entityId: entityId)
        noArtworkQueue.async(flags: .barrier) {
            self.noArtworkSet.add(key)
        }
    }
    
    /// Check if request is in-flight
    private func isInflightRequest(_ requestKey: String) -> Bool {
        inflightQueue.sync {
            let isInflight = inflightRequests.contains(requestKey)
            if !isInflight {
                inflightRequests.insert(requestKey)
            }
            return isInflight
        }
    }
    
    /// Mark request as in-flight or complete
    private func markInflightRequest(_ requestKey: String, inflight: Bool) {
        inflightQueue.sync {
            if inflight {
                inflightRequests.insert(requestKey)
            } else {
                inflightRequests.remove(requestKey)
            }
        }
    }
    
    // MARK: - Private Database Loading
    
    /// Load artwork data from database with appropriate fallback
    private func loadArtworkData(
        entityType: EntityType,
        entityId: Int64,
        completion: @escaping (Data?) -> Void
    ) {
        do {
            let data: Data?
            switch entityType {
            case .track:
                data = try loadTrackArtworkWithFallback(trackId: entityId)?.data
            case .album:
                data = try loadAlbumArtworkWithFallback(albumId: entityId)
            case .artist:
                data = try loadArtistArtworkWithFallback(artistId: entityId)
            }
            completion(data)
        } catch {
            Logger.warning("Failed to load artwork for \(entityType) \(entityId): \(error)")
            completion(nil)
        }
    }
    
    // MARK: - Private Image Processing
    
    /// Downsample image to target size for memory efficiency
    /// Uses high-quality Lanczos resampling for best visual quality
    private func downsampleImage(data: Data, targetSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        
        // Get original image dimensions
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = imageProperties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = imageProperties[kCGImagePropertyPixelHeight] as? CGFloat else {
            // Fallback to regular decoding if we can't get properties
            return NSImage(data: data)
        }
        
        // Calculate actual scale needed (use 2x for Retina displays)
        let scale: CGFloat = 2.0
        let maxDimension = max(pixelWidth, pixelHeight)
        let targetPixelSize = targetSize * scale
        
        // Only downsample if source is significantly larger
        if maxDimension <= targetPixelSize * 1.5 {
            // Image is already small enough, just decode it
            return NSImage(data: data)
        }
        
        // Create thumbnail with downsampling
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize,
            kCGImageSourceShouldCache: false  // We're doing our own caching
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fallback to regular decoding
            return NSImage(data: data)
        }
        
        // Convert CGImage to NSImage
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: size)
        
        return image
    }
    
    /// Calculate memory cost for an image
    private func calculateImageCost(_ image: NSImage) -> Int {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        // 4 bytes per pixel (RGBA)
        return width * height * 4
    }
    
    // MARK: - Private Database Fallback Logic
    
    /// Result type for track artwork (includes album ID for cache optimization)
    private struct TrackArtworkResult {
        let data: Data
        let albumId: Int64?
    }
    
    /// Load track artwork with fallback chain: album → track → nil
    /// Optimized: Uses DatabaseCache to avoid extra queries when possible
    private func loadTrackArtworkWithFallback(trackId: Int64) throws -> TrackArtworkResult? {
        // Try to get albumId from DatabaseCache first (zero DB queries)
        let cachedAlbumId = DatabaseCache.shared.track(trackId)?.albumId
        
        return try DatabaseManager.shared.dbQueue.read { db in
            var trackArtwork: Data?
            var albumId: Int64? = cachedAlbumId
            
            // Load album ID if not cached
            if albumId == nil {
                let row = try Row.fetchOne(db, sql: """
                    SELECT artwork_data, album_id
                    FROM tracks
                    WHERE id = ?
                    """, arguments: [trackId])
                
                guard let row = row else { return nil }
                
                trackArtwork = row["artwork_data"]
                albumId = row["album_id"]
            }
            
            // Prefer album artwork (most common case)
            if let albumId = albumId,
               let row = try Row.fetchOne(db, sql: """
                   SELECT artwork_data
                   FROM albums
                   WHERE id = ?
                   """, arguments: [albumId]),
               let albumArtwork = row["artwork_data"] as Data?,
               !albumArtwork.isEmpty {
                return TrackArtworkResult(data: albumArtwork, albumId: albumId)
            }
            
            // Load track artwork if we haven't yet
            if trackArtwork == nil {
                let row = try Row.fetchOne(db, sql: """
                    SELECT artwork_data
                    FROM tracks
                    WHERE id = ?
                    """, arguments: [trackId])
                trackArtwork = row?["artwork_data"]
            }
            
            // Fallback to track-specific artwork
            if let trackArtwork = trackArtwork, !trackArtwork.isEmpty {
                return TrackArtworkResult(data: trackArtwork, albumId: nil)
            }
            
            return nil
        }
    }
    
    /// Load album artwork with fallback chain: album → first track → nil
    private func loadAlbumArtworkWithFallback(albumId: Int64) throws -> Data? {
        try DatabaseManager.shared.dbQueue.read { db in
            // Try album's own artwork
            if let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM albums
                WHERE id = ?
                """, arguments: [albumId]),
               let albumArtwork = row["artwork_data"] as Data?,
               !albumArtwork.isEmpty {
                return albumArtwork
            }
            
            // Fallback: Use first track with artwork
            if let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM tracks
                WHERE album_id = ? AND artwork_data IS NOT NULL
                LIMIT 1
                """, arguments: [albumId]),
               let trackArtwork = row["artwork_data"] as Data?,
               !trackArtwork.isEmpty {
                return trackArtwork
            }
            
            return nil
        }
    }
    
    /// Load artist artwork (no fallback - artists have their own artwork or none)
    private func loadArtistArtworkWithFallback(artistId: Int64) throws -> Data? {
        try DatabaseManager.shared.dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT artwork_data
                FROM artists
                WHERE id = ?
                """, arguments: [artistId])
            
            guard let row = row,
                  let artistArtwork = row["artwork_data"] as Data?,
                  !artistArtwork.isEmpty else {
                return nil
            }
            
            return artistArtwork
        }
    }
}



