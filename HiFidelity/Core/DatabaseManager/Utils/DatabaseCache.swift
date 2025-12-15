//
//  DatabaseCache.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import Foundation
import Combine
import GRDB

// MARK: - Database Cache

/// In-memory cache for frequently accessed database data
/// Automatically invalidates when data changes
///
/// NOTE: This cache stores Track metadata WITHOUT artwork data.
/// For artwork, use ArtworkCache which provides lazy-loading with LRU eviction.
///
/// Thread-safe via internal cacheQueue for concurrent access
final class DatabaseCache: ObservableObject, @unchecked Sendable {
    // MARK: - Singleton
    static let shared = DatabaseCache()
    
    // MARK: - Published Properties
    @Published private(set) var folders: [Folder] = []
    @Published private(set) var allTracks: [Track] = []
    @Published private(set) var allPlaylists: [Playlist] = []
    @Published private(set) var isLoading = false
    
    // MARK: - Thread Safety
    private let cacheQueue = DispatchQueue(label: "com.hifidelity.databasecache", attributes: .concurrent)
    
    // MARK: - Cache State
    private var foldersCache: [Folder]?
    private var folderTracksCache: [Int64: [Track]] = [:] // folderId -> tracks
    private var allTracksCache: [Track]?
    private var trackCache: [Int64: Track] = [:] // trackId -> track (thread-safe via cacheQueue)
    private var playlistsCache: [Playlist]?
    
    private var lastFolderRefresh: Date?
    private var lastTrackRefresh: Date?
    private var lastPlaylistRefresh: Date?
    
    // Cache TTL (time-to-live) - refresh after this duration
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Invalidate all caches when library data changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateCache),
            name: .libraryDataDidChange,
            object: nil
        )
        
        // Invalidate folders cache when folders change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidateFoldersCache),
            name: .foldersDataDidChange,
            object: nil
        )
        
        // Invalidate only playlist cache when playlists change
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(invalidatePlaylistsCache),
            name: .playlistsDidChange,
            object: nil
        )
    }
    
    @objc private func invalidateCache() {
        Logger.debug("Cache invalidated due to library data change")
        foldersCache = nil
        folderTracksCache.removeAll()
        allTracksCache = nil
        
        // Thread-safe clear of trackCache
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.trackCache.removeAll()
        }
        
        playlistsCache = nil
        lastFolderRefresh = nil
        lastTrackRefresh = nil
        lastPlaylistRefresh = nil
        
        // Also clear artwork cache since tracks may have changed
        Task {
            ArtworkCache.shared.clearAll()
        }
    }
    
    @objc private func invalidateFoldersCache() {
        Logger.debug("Folders cache invalidated due to folder change")
        foldersCache = nil
        lastFolderRefresh = nil
        
        // Notify UI to refresh
        Task { @MainActor in
            self.objectWillChange.send()
        }
    }
    
    @objc private func invalidatePlaylistsCache() {
        performPlaylistCacheInvalidation()
    }
    
    private func performPlaylistCacheInvalidation() {
        Logger.debug("Playlist cache invalidated")
        playlistsCache = nil
        lastPlaylistRefresh = nil
        
        // Notify UI to refresh
        Task { @MainActor in
            self.objectWillChange.send()
        }
    }
    
    // MARK: - Folders
    
    /// Get folders from cache or database
    func getFolders(forceRefresh: Bool = false) async throws -> [Folder] {
        // Check if we need to refresh
        let needsRefresh = forceRefresh ||
                          foldersCache == nil ||
                          shouldRefreshCache(lastRefresh: lastFolderRefresh)
        
        if needsRefresh {
            Logger.debug("Refreshing folders cache from database")
            let folders = try await DatabaseManager.shared.dbQueue.read { db in
                try Folder.order(Folder.Columns.name).fetchAll(db)
            }
            
            foldersCache = folders
            lastFolderRefresh = Date()
            
            // Update published property on main thread
            await MainActor.run {
                self.folders = folders
            }
        }
        
        return foldersCache ?? []
    }
    
    // MARK: - Tracks
    
    /// Get all tracks (lightweight, WITHOUT artwork data) from cache or database
    /// Use ArtworkCache to load artwork on-demand
    func getAllTracks(forceRefresh: Bool = false) async throws -> [Track] {
        let needsRefresh = forceRefresh ||
                          allTracksCache == nil ||
                          shouldRefreshCache(lastRefresh: lastTrackRefresh)
        
        if needsRefresh {
            Logger.debug("Refreshing all tracks cache from database")
            let tracks = try await DatabaseManager.shared.dbQueue.read { db in
                try Track.lightweightRequest().fetchAll(db)
            }
            
            allTracksCache = tracks
            lastTrackRefresh = Date()
            
            // Populate track cache for quick lookups (thread-safe)
            cacheQueue.async(flags: .barrier) { [weak self] in
                for track in tracks {
                    if let trackId = track.trackId {
                        self?.trackCache[trackId] = track
                    }
                }
            }
            
            await MainActor.run {
                self.allTracks = tracks
            }
        }
        
        return allTracksCache ?? []
    }
    
    /// Get tracks for a specific folder (lightweight, WITHOUT artwork data)
    /// Use ArtworkCache to load artwork on-demand
    func getTracks(for folder: Folder, forceRefresh: Bool = false) async throws -> [Track] {
        if let folderId = folder.id {
            // Real folder - check cache
            if !forceRefresh, let cached = folderTracksCache[folderId] {
                Logger.debug("Using cached tracks for folder: \(folder.name)")
                return cached
            }
            
            // Load from database
            Logger.debug("Loading tracks for folder: \(folder.name)")
            let tracks = try await DatabaseManager.shared.dbQueue.read { db in
                try Track.lightweightRequest()
                    .filter(Track.Columns.folderId == folderId)
                    .fetchAll(db)
            }
            
            folderTracksCache[folderId] = tracks
            
            // Populate track cache for quick lookups (thread-safe)
            cacheQueue.async(flags: .barrier) { [weak self] in
                for track in tracks {
                    if let trackId = track.trackId {
                        self?.trackCache[trackId] = track
                    }
                }
            }
            
            return tracks
            
        } else {
            // Virtual folder - filter from all tracks
            let allTracks = try await getAllTracks(forceRefresh: forceRefresh)
            let folderPath = folder.url.path
            
            return allTracks.filter { track in
                track.url.deletingLastPathComponent().path == folderPath
            }
        }
    }
    
    /// Get a single track by ID (lightweight, WITHOUT artwork data)
    /// Use ArtworkCache to load artwork on-demand
    func getTrack(by id: Int64, forceRefresh: Bool = false) async throws -> Track? {
        // Check cache first (thread-safe)
        if !forceRefresh {
            let cached = cacheQueue.sync { trackCache[id] }
            if let cached = cached {
                Logger.debug("Using cached track for ID: \(id)")
                return cached
            }
        }
        
        // Load from database
        Logger.debug("Loading track from database for ID: \(id)")
        let track = try await DatabaseManager.shared.dbQueue.read { db in
            try Track.lightweightRequest()
                .filter(Track.Columns.trackId == id)
                .fetchOne(db)
        }
        
        // Cache if found (thread-safe)
        if let track = track {
            cacheQueue.async(flags: .barrier) { [weak self] in
                self?.trackCache[id] = track
            }
        }
        
        return track
    }
    
    func track(_ id: Int64) -> Track? {
        cacheQueue.sync {
            trackCache[id]
        }
    }
    
    // MARK: - Playlists
    
    /// Get all playlists from cache or database
    func getAllPlaylists(forceRefresh: Bool = false) async throws -> [Playlist] {
        let needsRefresh = forceRefresh ||
                          playlistsCache == nil ||
                          shouldRefreshCache(lastRefresh: lastPlaylistRefresh)
        
        if needsRefresh {
            Logger.debug("Refreshing playlists cache from database")
            let playlists = try await DatabaseManager.shared.getAllPlaylists()
            
            playlistsCache = playlists
            lastPlaylistRefresh = Date()
            
            // Update published property on main thread
            await MainActor.run {
                self.allPlaylists = playlists
            }
        }
        
        return playlistsCache ?? []
    }
    
    /// Get user playlists only (excluding smart playlists)
    func getUserPlaylists(forceRefresh: Bool = false) async throws -> [Playlist] {
        let allPlaylists = try await getAllPlaylists(forceRefresh: forceRefresh)
        return allPlaylists.filter { !$0.isSmart }
    }
    
    /// Manually invalidate playlists cache
    /// Note: This is automatically called when .playlistsDidChange notification is posted
    func invalidatePlaylists() {
        performPlaylistCacheInvalidation()
    }
    
    // MARK: - Cache Management
    
    private func shouldRefreshCache(lastRefresh: Date?) -> Bool {
        guard let lastRefresh = lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > cacheTTL
    }
    
    /// Manually invalidate specific folder's tracks
    func invalidateFolderTracks(_ folderId: Int64) {
        folderTracksCache.removeValue(forKey: folderId)
        Logger.debug("Invalidated tracks cache for folder ID: \(folderId)")
    }
    
    /// Manually invalidate a specific track
    func invalidateTrack(_ trackId: Int64) {
        trackCache.removeValue(forKey: trackId)
        Logger.debug("Invalidated track cache for track ID: \(trackId)")
    }
    
    /// Manually refresh all caches
    func refreshAll() async throws {
        Logger.info("Refreshing all caches")
        _ = try await getFolders(forceRefresh: true)
        _ = try await getAllTracks(forceRefresh: true)
        _ = try await getAllPlaylists(forceRefresh: true)
    }
    
    /// Clear all caches and free memory
    func clearAll() {
        invalidateCache()
        Logger.info("All caches cleared")
        
        // Also clear artwork cache
        Task {
            ArtworkCache.shared.clearAll()
        }
    }
    
    // MARK: - Statistics
    
    func getCacheStats() -> CacheStats {
        CacheStats(
            foldersCount: foldersCache?.count ?? 0,
            allTracksCount: allTracksCache?.count ?? 0,
            cachedFolderTracksCount: folderTracksCache.count,
            cachedTracksCount: trackCache.count,
            playlistsCount: playlistsCache?.count ?? 0,
            lastFolderRefresh: lastFolderRefresh,
            lastTrackRefresh: lastTrackRefresh,
            lastPlaylistRefresh: lastPlaylistRefresh
        )
    }
    
    // MARK: - Library Statistics
    
    /// Get total storage usage of all tracks in bytes
    /// Uses efficient database aggregation instead of loading all tracks
    func getTotalStorageUsage() async throws -> Int64 {
        try await DatabaseManager.shared.dbQueue.read { db in
            try Track
                .select(sum(Track.Columns.fileSize), as: Int64.self)
                .fetchOne(db) ?? 0
        }
    }
    
    /// Get library statistics
    func getLibraryStats() async throws -> LibraryStats {
        try await DatabaseManager.shared.dbQueue.read { db in
            let totalTracks = try Track.fetchCount(db)
            let totalStorage = try Track
                .select(sum(Track.Columns.fileSize), as: Int64.self)
                .fetchOne(db) ?? 0
            let totalDuration = try Track
                .select(sum(Track.Columns.duration), as: Double.self)
                .fetchOne(db) ?? 0
            let totalFolders = try Folder.fetchCount(db)
            
            return LibraryStats(
                totalTracks: totalTracks,
                totalStorage: totalStorage,
                totalDuration: totalDuration,
                totalFolders: totalFolders
            )
        }
    }
}

// MARK: - Cache Statistics

struct CacheStats {
    let foldersCount: Int
    let allTracksCount: Int
    let cachedFolderTracksCount: Int
    let cachedTracksCount: Int
    let playlistsCount: Int
    let lastFolderRefresh: Date?
    let lastTrackRefresh: Date?
    let lastPlaylistRefresh: Date?
    
    var description: String {
        """
        Cache Statistics:
        - Folders: \(foldersCount)
        - All Tracks: \(allTracksCount)
        - Folder Tracks Cached: \(cachedFolderTracksCount)
        - Individual Tracks Cached: \(cachedTracksCount)
        - Playlists: \(playlistsCount)
        - Last Folder Refresh: \(lastFolderRefresh?.formatted() ?? "Never")
        - Last Track Refresh: \(lastTrackRefresh?.formatted() ?? "Never")
        - Last Playlist Refresh: \(lastPlaylistRefresh?.formatted() ?? "Never")
        """
    }
}

// MARK: - Library Statistics

struct LibraryStats {
    let totalTracks: Int
    let totalStorage: Int64      // in bytes
    let totalDuration: Double    // in seconds
    let totalFolders: Int
    
    var formattedStorage: String {
        ByteCountFormatter.string(fromByteCount: totalStorage, countStyle: .file)
    }
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) minutes"
        }
    }
    
    var averageTrackSize: Int64 {
        totalTracks > 0 ? totalStorage / Int64(totalTracks) : 0
    }
    
    var description: String {
        """
        Library Statistics:
        - Total Tracks: \(totalTracks.formatted())
        - Total Storage: \(formattedStorage)
        - Total Duration: \(formattedDuration)
        - Total Folders: \(totalFolders)
        - Average Track Size: \(ByteCountFormatter.string(fromByteCount: averageTrackSize, countStyle: .file))
        """
    }
}

