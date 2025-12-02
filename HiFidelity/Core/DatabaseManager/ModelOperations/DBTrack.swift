//
//  DBTrack.swift
//  HiFidelity
//
//  Created by Varun Rathod on 30/10/25.
//

import Foundation
import GRDB

// MARK: - Local Enums

enum TrackProcessResult {
    case new(Track, TrackMetadata)
    case update(Track, TrackMetadata)
    case skipped
}

// This extension contains methods for track processing as found from folders added.
extension DatabaseManager {
    /// Process a new batch of music files with normalized data support
    /// - Parameters:
    ///   - batch: Array of (url, folderId) tuples to process
    ///   - existingTracks: Dictionary of existing tracks indexed by URL for update checking
    /// - Note: Checks for duplicates, extracts metadata concurrently, updates or inserts in single transaction
    func processBatch(_ batch: [(url: URL, folderId: Int64)], existingTracks: [URL: Track] = [:]) async throws {
        guard !batch.isEmpty else { return }
       
        let metadataResults = try await withThrowingTaskGroup(
            of: (URL, TrackProcessResult).self
        ) { group in
            for (fileURL, folderId) in batch {
                group.addTask {
                    do {
                        // Check if track already exists
                        if let existingTrack = existingTracks[fileURL] {
                            // Check if file was modified
                            let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                            if let fileModDate = attributes.contentModificationDate,
                               let dbModDate = existingTrack.dateModified {
                                
                                // File was modified, update metadata
                                if fileModDate > dbModDate {
                                    var updatedTrack = existingTrack
                                    let metadata = TagLibMetadataManager.extractMetadata(from: fileURL)
                                    TagLibMetadataManager.applyMetadata(to: &updatedTrack, from: metadata, at: fileURL)
                                    
                                    Logger.info("File modified, updating metadata: \(fileURL.lastPathComponent)")
                                    return (fileURL, TrackProcessResult.update(updatedTrack, metadata))
                                } else {
                                    // File unchanged, skip
                                    return (fileURL, TrackProcessResult.skipped)
                                }
                            }
                        }
                        
                        // New track - extract metadata and prepare for insertion
                        var track = Track(url: fileURL)
                        let metadata = TagLibMetadataManager.extractMetadata(from: fileURL)
                        track.folderId = folderId
                        TagLibMetadataManager.applyMetadata(to: &track, from: metadata, at: fileURL)
                        
                        return (fileURL, TrackProcessResult.new(track, metadata))
                        
                    } catch {
                        Logger.error("Failed to process track \(fileURL.lastPathComponent): \(error)")
                        return (fileURL, TrackProcessResult.skipped)
                    }
                }
            }
            
            // Collect all results
            var results: [(URL, TrackProcessResult)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        // Step 4: Separate new, update, and skipped tracks
        var newTracks: [(Track, TrackMetadata)] = []
        var updatedTracks: [(Track, TrackMetadata)] = []
        var skippedCount = 0
        
        for (_, result) in metadataResults {
            switch result {
            case .new(let track, let metadata):
                newTracks.append((track, metadata))
            case .update(let track, let metadata):
                updatedTracks.append((track, metadata))
            case .skipped:
                skippedCount += 1
            }
        }
        
        // Step 5: Insert and update all in single transaction for atomicity
        guard !newTracks.isEmpty || !updatedTracks.isEmpty else {
            Logger.info("Batch complete: \(skippedCount) unchanged")
            return
        }
        
        let (insertedCount, updatedCount) = try await dbQueue.write { [newTracks, updatedTracks] db -> (Int, Int) in
            var inserted = 0
            var updated = 0
            
            // Insert new tracks
            for (track, metadata) in newTracks {
                do {
                    try self.processNewTrack(track, metadata: metadata, in: db)
                    inserted += 1
                } catch {
                    Logger.error("Failed to insert track '\(track.title)': \(error)")
                }
            }
            
            // Update existing tracks
            for (track, metadata) in updatedTracks {
                do {
                    try self.processUpdatedTrack(track, metadata: metadata, in: db)
                    updated += 1
                } catch {
                    Logger.error("Failed to update track '\(track.title)': \(error)")
                }
            }
            
            return (inserted, updated)
        }
        
        Logger.info("Batch complete: \(insertedCount) inserted, \(updatedCount) updated, \(skippedCount) unchanged")
    }
    
    // MARK: - Track Processing
    
    /// Process a new track with normalized data
    private func processNewTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws {
        var mutableTrack = track
        
        // Determine where to store artwork based on album validity
        let hasValidAlbum = !track.album.isEmpty && track.album != "Unknown Album"
        
        // Create/get normalized entities and link them
        mutableTrack.albumId = try DatabaseManager.getOrCreateAlbum(
            in: db,
            title: track.album,
            albumArtist: track.albumArtist,
            artist: track.artist,
            year: track.year,
            releaseType: metadata.extended.releaseType,
            recordLabel: metadata.extended.label,
            musicbrainzAlbumId: metadata.extended.musicBrainzAlbumId,
            releaseDate: metadata.releaseDate,
            musicbrainzReleaseGroupId: metadata.extended.musicBrainzReleaseGroupId,
            barcode: metadata.extended.barcode,
            catalogNumber: metadata.extended.catalogNumber,
            releaseCountry: metadata.extended.releaseCountry
        )
        
        mutableTrack.artistId = try DatabaseManager.getOrCreateArtist(
            in: db,
            name: track.artist,
            musicbrainzArtistId: metadata.extended.musicBrainzArtistId,
            artistType: metadata.extended.artistType,
            country: metadata.extended.releaseCountry
        )
        
        mutableTrack.genreId = try DatabaseManager.getOrCreateGenre(
            in: db,
            name: track.genre,
            style: nil  // Style is typically not in tags; could be inferred later
        )
        
        // Store artwork appropriately
        if let artworkData = metadata.artworkData {
            let artworkSourceType: String
            if hasValidAlbum, let albumId = mutableTrack.albumId {
                // Store artwork in album table
                try storeAlbumArtwork(albumId: albumId, artworkData: artworkData, in: db)
                // Remove artwork from track to save space
                mutableTrack.artworkData = nil
                artworkSourceType = "album"
            } else {
                // Store artwork in track table (for tracks without proper album)
                mutableTrack.artworkData = artworkData
                artworkSourceType = "track"
            }
            
            // Also store artwork in artist table if artist exists
            if let artistId = mutableTrack.artistId {
                try storeArtistArtwork(artistId: artistId, artworkData: artworkData, sourceType: artworkSourceType, in: db)
            }
        }
        
        // Insert the track - didInsert() automatically sets trackId
        try mutableTrack.insert(db)
        
        // Verify insertion succeeded
        guard let trackId = mutableTrack.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        // Note: Statistics are automatically updated by database triggers
        
        Logger.info("Added new track: \(mutableTrack.title) (ID: \(trackId))")
        
        // Log interesting metadata in debug builds
        #if DEBUG
        logTrackMetadata(mutableTrack)
        #endif
    }
    
    /// Process an updated track with normalized data
    private func processUpdatedTrack(_ track: Track, metadata: TrackMetadata, in db: Database) throws {
        var mutableTrack = track
        
        // Determine where to store artwork based on album validity
        let hasValidAlbum = !track.album.isEmpty && track.album != "Unknown Album"
        
        // Create/get normalized entities and link them
        mutableTrack.albumId = try DatabaseManager.getOrCreateAlbum(
            in: db,
            title: track.album,
            albumArtist: track.albumArtist,
            artist: track.artist,
            year: track.year,
            releaseType: metadata.extended.releaseType,
            recordLabel: metadata.extended.label,
            musicbrainzAlbumId: metadata.extended.musicBrainzAlbumId,
            releaseDate: metadata.releaseDate,
            musicbrainzReleaseGroupId: metadata.extended.musicBrainzReleaseGroupId,
            barcode: metadata.extended.barcode,
            catalogNumber: metadata.extended.catalogNumber,
            releaseCountry: metadata.extended.releaseCountry
        )
        
        mutableTrack.artistId = try DatabaseManager.getOrCreateArtist(
            in: db,
            name: track.artist,
            musicbrainzArtistId: metadata.extended.musicBrainzArtistId,
            artistType: metadata.extended.artistType,
            country: metadata.extended.releaseCountry
        )
        
        mutableTrack.genreId = try DatabaseManager.getOrCreateGenre(
            in: db,
            name: track.genre,
            style: nil  // Style is typically not in tags; could be inferred later
        )
        
        // Update artwork storage if metadata contains artwork
        if let artworkData = metadata.artworkData {
            let artworkSourceType: String
            if hasValidAlbum, let albumId = mutableTrack.albumId {
                // Store artwork in album table
                try storeAlbumArtwork(albumId: albumId, artworkData: artworkData, in: db)
                // Remove artwork from track to save space
                mutableTrack.artworkData = nil
                artworkSourceType = "album"
            } else {
                // Store artwork in track table (for tracks without proper album)
                mutableTrack.artworkData = artworkData
                artworkSourceType = "track"
            }
            
            // Also store artwork in artist table if artist exists
            if let artistId = mutableTrack.artistId {
                try storeArtistArtwork(artistId: artistId, artworkData: artworkData, sourceType: artworkSourceType, in: db)
            }
        }
        
        // Update the track
        try mutableTrack.update(db)
        
        guard let trackId = mutableTrack.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        // Note: Statistics are automatically updated by database triggers
        // The triggers handle both old and new entity statistics when IDs change
        
        Logger.info("Updated track: \(mutableTrack.title) (ID: \(trackId))")
    }
    
    // MARK: - Metadata Logging
    
    private func logTrackMetadata(_ track: Track) {
        // Log interesting metadata for debugging
        if let extendedMetadata = track.extendedMetadata {
            var interestingFields: [String] = []
            
            if let isrc = extendedMetadata.isrc { interestingFields.append("ISRC: \(isrc)") }
            if let label = extendedMetadata.label { interestingFields.append("Label: \(label)") }
            if let conductor = extendedMetadata.conductor { interestingFields.append("Conductor: \(conductor)") }
            if let producer = extendedMetadata.producer { interestingFields.append("Producer: \(producer)") }
            
            if !interestingFields.isEmpty {
                Logger.info("Extended metadata: \(interestingFields.joined(separator: ", "))")
            }
        }
        
        // Log multi-artist info
        if track.artist.contains(";") || track.artist.contains(",") || track.artist.contains("&") {
            Logger.info("Multi-artist track: \(track.artist)")
        }
        
        // Log album artist if different from artist
        if let albumArtist = track.albumArtist, albumArtist != track.artist {
            Logger.info("Album artist differs: \(albumArtist)")
        }
    }
    
    func getTracksInFolder(_ folder: Folder) -> [Track] {
        guard let folderId = folder.id else { return [] }
        return getTracksForFolder(folderId)
    }
    
    func getTracksForFolder(_ folderId: Int64) -> [Track] {
        do {
            let tracks = try dbQueue.read { db in
                try Track.lightweightRequest()
                    .filter(Track.Columns.folderId == folderId)
                    .order(Track.Columns.title)
                    .fetchAll(db)
            }
            
            return tracks
        } catch {
            Logger.error("Failed to fetch tracks for folder: \(error)")
            return []
        }
    }
    
    
    // Updates a track's favorite status
    func updateTrackFavoriteStatus(_ track: Track) async throws {
        _ = try await dbQueue.write { db in
            try track
                .update(db, columns: [Track.Columns.isFavorite])
        }
    }

    // Updates a track's play count and last played date
    func updateTrackPlayInfo(_ track: Track) async throws {
        _ = try await dbQueue.write { db in
            try track
                .update(db, columns: [Track.Columns.playCount, Track.Columns.lastPlayedDate])
        }
    }
    
    // MARK: - Path Management
    
    /// Update a single track's path in the database
    func updateTrackPath(trackId: Int64, newPath: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE tracks SET path = ? WHERE id = ?",
                arguments: [newPath, trackId]
            )
        }
        
        Logger.debug("Updated track path for ID \(trackId)")
    }
    
    /// Bulk update track paths (for folder relocation)
    /// Replaces oldPathPrefix with newPathPrefix for all matching tracks
    func bulkUpdateTrackPaths(oldPathPrefix: String, newPathPrefix: String) async throws -> Int {
        let count = try await dbQueue.write { db -> Int in
            // Get all affected tracks
            let affectedTracks = try Track
                .filter(Track.Columns.path.like("\(oldPathPrefix)%"))
                .fetchAll(db)
            
            var updatedCount = 0
            
            // Update each track's path
            for track in affectedTracks {
                let relativePath = String(track.url.path.dropFirst(oldPathPrefix.count))
                let newPath = newPathPrefix + relativePath
                
                // Verify file exists at new location before updating
                if FileManager.default.fileExists(atPath: newPath) {
                    try db.execute(
                        sql: "UPDATE tracks SET path = ? WHERE id = ?",
                        arguments: [newPath, track.trackId]
                    )
                    updatedCount += 1
                } else {
                    Logger.warning("Skipping track - file not found at new location: \(track.filename)")
                }
            }
            
            return updatedCount
        }
        
        Logger.info("Bulk updated \(count) track paths")
        return count
    }
    
    /// Get all tracks with missing files (for health check)
    func getTracksWithMissingFiles() async throws -> [Track] {
        try await dbQueue.read { db in
            let allTracks = try Track.lightweightRequest().fetchAll(db)
            
            return allTracks.filter { track in
                !FileManager.default.fileExists(atPath: track.url.path)
            }
        }
    }
    
    /// Verify track paths and return count of missing files
    func verifyTrackPaths() async throws -> (total: Int, missing: Int) {
        try await dbQueue.read { db in
            let allTracks = try Track
                .select(Track.Columns.path)
                .fetchAll(db)
            
            let totalCount = allTracks.count
            let missingCount = allTracks.filter { track in
                !FileManager.default.fileExists(atPath: track.url.path)
            }.count
            
            return (total: totalCount, missing: missingCount)
        }
    }
    
    // MARK: - Artwork Storage
    
    /// Store artwork data in the album table if not already present
    /// Only updates if album doesn't have artwork yet to preserve user-set custom artwork
    private func storeAlbumArtwork(albumId: Int64, artworkData: Data, in db: Database) throws {
        // Check if album already has artwork
        let hasArtwork = try Album
            .select(Album.Columns.artworkData)
            .filter(Album.Columns.id == albumId)
            .fetchOne(db)
            .flatMap { (row: Row) -> Data? in
                row[Album.Columns.artworkData] as Data?
            } != nil
        
        // Only update if album doesn't have artwork
        if !hasArtwork {
            try db.execute(
                sql: """
                UPDATE albums 
                SET artwork_data = ?
                WHERE id = ?
                """,
                arguments: [artworkData, albumId]
            )
            Logger.info("Stored artwork for album ID: \(albumId)")
        }
    }
    
    /// Store artwork data in the artist table if not already present
    /// Only updates if artist doesn't have artwork yet to preserve user-set custom artwork
    /// - Parameters:
    ///   - artistId: Artist ID to update
    ///   - artworkData: Artwork binary data
    ///   - sourceType: Source of artwork: "album", "track", or "custom"
    ///   - db: Database connection
    private func storeArtistArtwork(artistId: Int64, artworkData: Data, sourceType: String, in db: Database) throws {
        // Check if artist already has artwork
        let hasArtwork = try Artist
            .select(Artist.Columns.artworkData)
            .filter(Artist.Columns.id == artistId)
            .fetchOne(db)
            .flatMap { (row: Row) -> Data? in
                row[Artist.Columns.artworkData] as Data?
            } != nil
        
        // Only update if artist doesn't have artwork
        if !hasArtwork {
            try db.execute(
                sql: """
                UPDATE artists 
                SET artwork_data = ?, artwork_source_type = ?
                WHERE id = ?
                """,
                arguments: [artworkData, sourceType, artistId]
            )
            Logger.info("Stored artwork for artist ID: \(artistId) from source: \(sourceType)")
        }
    }
    
}

