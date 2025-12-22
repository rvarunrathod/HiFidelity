//
//  DBNormalizedEntities.swift
//  HiFidelity
//
//  Database operations for normalized entities (Albums, Artists, Genres)
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Album Operations
    
    /// Get or create an album entity and return its ID
    /// - Parameters:
    ///   - db: Database connection
    ///   - title: Album title
    ///   - albumArtist: Album artist (or nil)
    ///   - artist: Track artist (fallback if no album artist)
    ///   - year: Release year
    ///   - releaseType: Album type (Album, EP, Single, etc.)
    ///   - recordLabel: Record label name
    ///   - musicbrainzAlbumId: MusicBrainz Album ID
    ///   - releaseDate: Full release date
    ///   - musicbrainzReleaseGroupId: MusicBrainz Release Group ID
    ///   - barcode: UPC/EAN barcode
    ///   - catalogNumber: Catalog number
    ///   - releaseCountry: ISO country code
    /// - Returns: Album ID or nil if title is empty/unknown
    static func getOrCreateAlbum(
        in db: Database,
        title: String,
        albumArtist: String?,
        artist: String,
        year: String,
        releaseType: String? = nil,
        recordLabel: String? = nil,
        musicbrainzAlbumId: String? = nil,
        releaseDate: String? = nil,
        musicbrainzReleaseGroupId: String? = nil,
        barcode: String? = nil,
        catalogNumber: String? = nil,
        releaseCountry: String? = nil
    ) throws -> Int64? {
        guard !title.isEmpty, title != "Unknown Album" else { return nil }
        
        let effectiveAlbumArtist = albumArtist
        let normalizedName = title.normalized
        
        // Try to find existing album using normalized name for better deduplication
        // e.g., "The Beatles" and "Beatles" will match
        if let existing = try Album
            .filter(Album.Columns.normalizedName == normalizedName)
            .fetchOne(db) {
            return existing.id
        }
        
        // Create new album with normalized and sort names
        var album = Album(
            id: nil,
            title: title,
            normalizedName: normalizedName,
            sortName: title.sortName,
            albumArtist: effectiveAlbumArtist,
            year: year,
            releaseType: releaseType,
            recordLabel: recordLabel,
            discCount: 1,
            musicbrainzAlbumId: musicbrainzAlbumId,
            releaseDate: releaseDate,
            musicbrainzReleaseGroupId: musicbrainzReleaseGroupId,
            barcode: barcode,
            catalogNumber: catalogNumber,
            releaseCountry: releaseCountry,
            trackCount: 0,
            totalDuration: 0,
            isCompilation: false,
            artworkData: nil,
            dateAdded: Date()
        )
        try album.insert(db)
        
        Logger.info("Created new album: \(title) [sort: \(album.sortName), normalized: \(normalizedName)]")
        return album.id
    }
    
    /// Update album statistics
    /// - Parameters:
    ///   - db: Database connection
    ///   - albumId: Album ID to update
    static func updateAlbumStatistics(in db: Database, albumId: Int64) throws {
        let trackCount = try Track
            .filter(Track.Columns.albumId == albumId)
            .fetchCount(db)
        
        let totalDuration = try Track
            .filter(Track.Columns.albumId == albumId)
            .select(sum(Track.Columns.duration))
            .fetchOne(db) ?? 0
        
        try db.execute(sql: """
            UPDATE albums 
            SET track_count = ?, total_duration = ?
            WHERE id = ?
            """,
            arguments: [trackCount, totalDuration, albumId]
        )
    }
    
    // MARK: - Artist Operations
    
    /// Get or create an artist entity and return its ID
    /// - Parameters:
    ///   - db: Database connection
    ///   - name: Artist name
    ///   - musicbrainzArtistId: MusicBrainz Artist ID
    ///   - artistType: Artist type (Person, Group, etc.)
    ///   - country: ISO country code
    /// - Returns: Artist ID or nil if name is empty/unknown
    static func getOrCreateArtist(
        in db: Database,
        name: String,
        musicbrainzArtistId: String? = nil,
        artistType: String? = nil,
        country: String? = nil
    ) throws -> Int64? {
        guard !name.isEmpty, name != "Unknown Artist" else { return nil }
        
        let normalizedName = name.normalized
        
        // Try to find existing artist using normalized name for better deduplication
        // e.g., "The Beatles" and "Beatles" will match
        if let existing = try Artist
            .filter(Artist.Columns.normalizedName == normalizedName)
            .fetchOne(db) {
            return existing.id
        }
        
        // Create new artist with normalized and sort names
        var artist = Artist(
            id: nil,
            name: name,
            normalizedName: normalizedName,
            sortName: name.sortName,
            musicbrainzArtistId: musicbrainzArtistId,
            artistType: artistType,
            country: country,
            trackCount: 0,
            albumCount: 0,
            dateAdded: Date()
        )
        try artist.insert(db)
        
        Logger.info("Created new artist: \(name) [sort: \(artist.sortName), normalized: \(normalizedName)]")
        return artist.id
    }
    
    /// Update artist statistics
    /// - Parameters:
    ///   - db: Database connection
    ///   - artistId: Artist ID to update
    static func updateArtistStatistics(in db: Database, artistId: Int64) throws {
        let trackCount = try Track
            .filter(Track.Columns.artistId == artistId)
            .fetchCount(db)
        
        let albumCount = try Track
            .filter(Track.Columns.artistId == artistId)
            .filter(Track.Columns.albumId != nil)
            .select(count(distinct: Track.Columns.albumId))
            .fetchOne(db) ?? 0
        
        try db.execute(sql: """
            UPDATE artists 
            SET track_count = ?, album_count = ?
            WHERE id = ?
            """,
            arguments: [trackCount, albumCount, artistId]
        )
    }
    
    // MARK: - Genre Operations
    
    /// Get or create a genre entity and return its ID
    /// - Parameters:
    ///   - db: Database connection
    ///   - name: Genre name
    ///   - style: Sub-genre or style
    /// - Returns: Genre ID or nil if name is empty/unknown
    static func getOrCreateGenre(
        in db: Database,
        name: String,
        style: String? = nil
    ) throws -> Int64? {
        guard !name.isEmpty, name != "Unknown Genre" else { return nil }
        
        let normalizedName = name.normalized
        
        // Try to find existing genre using normalized name for better deduplication
        // e.g., "Rock & Roll" and "Rock  Roll" will match
        if let existing = try Genre
            .filter(Genre.Columns.normalizedName == normalizedName)
            .fetchOne(db) {
            return existing.id
        }
        
        // Create new genre with normalized and sort names
        var genre = Genre(
            id: nil,
            name: name,
            normalizedName: normalizedName,
            sortName: name.sortName,
            style: style,
            trackCount: 0,
            dateAdded: Date()
        )
        try genre.insert(db)
        
        Logger.info("Created new genre: \(name) [sort: \(genre.sortName), normalized: \(normalizedName)]")
        return genre.id
    }
    
    /// Update genre statistics
    /// - Parameters:
    ///   - db: Database connection
    ///   - genreId: Genre ID to update
    static func updateGenreStatistics(in db: Database, genreId: Int64) throws {
        let trackCount = try Track
            .filter(Track.Columns.genreId == genreId)
            .fetchCount(db)
        
        try db.execute(sql: """
            UPDATE genres 
            SET track_count = ?
            WHERE id = ?
            """,
            arguments: [trackCount, genreId]
        )
    }
    
    // MARK: - Batch Update
    
    /// Update statistics for multiple entities at once
    /// - Parameters:
    ///   - db: Database connection
    ///   - albumId: Optional album ID
    ///   - artistId: Optional artist ID
    ///   - genreId: Optional genre ID
    static func updateEntityStatistics(
        in db: Database,
        albumId: Int64? = nil,
        artistId: Int64? = nil,
        genreId: Int64? = nil
    ) throws {
        if let albumId = albumId {
            try updateAlbumStatistics(in: db, albumId: albumId)
        }
        
        if let artistId = artistId {
            try updateArtistStatistics(in: db, artistId: artistId)
        }
        
        if let genreId = genreId {
            try updateGenreStatistics(in: db, genreId: genreId)
        }
    }
    
    // MARK: - Query Operations
    
    /// Get all albums, sorted by title
    func getAllAlbums() async throws -> [Album] {
        return try await dbQueue.read { db in
            try Album
                .order(Album.Columns.title)
                .fetchAll(db)
        }
    }
    
    /// Get all artists, sorted by name
    func getAllArtists() async throws -> [Artist] {
        return try await dbQueue.read { db in
            try Artist
                .order(Artist.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Get all genres, sorted by name
    func getAllGenres() async throws -> [Genre] {
        return try await dbQueue.read { db in
            try Genre
                .order(Genre.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Get tracks for a specific album
    /// - Parameter albumId: Album ID
    /// - Returns: Array of tracks in the album
    func getTracksForAlbum(_ albumId: Int64) async throws -> [Track] {
        return try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.albumId == albumId)
                .order(Track.Columns.discNumber, Track.Columns.trackNumber)
                .fetchAll(db)
        }
    }
    
    /// Get tracks for a specific artist
    /// - Parameter artistId: Artist ID
    /// - Returns: Array of tracks by the artist
    func getTracksForArtist(_ artistId: Int64) async throws -> [Track] {
        return try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.artistId == artistId)
                .order(Track.Columns.album, Track.Columns.trackNumber)
                .fetchAll(db)
        }
    }
    
    /// Get tracks for a specific genre
    /// - Parameter genreId: Genre ID
    /// - Returns: Array of tracks in the genre
    func getTracksForGenre(_ genreId: Int64) async throws -> [Track] {
        return try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.genreId == genreId)
                .order(Track.Columns.artist, Track.Columns.album, Track.Columns.trackNumber)
                .fetchAll(db)
        }
    }
    
    // MARK: - Search Operations (Using Normalized Names)
    
    /// Search albums using normalized name for better matching
    /// - Parameter query: Search query
    /// - Returns: Array of matching albums
    func searchAlbums(query: String) async throws -> [Album] {
        let normalizedQuery = query.normalized
        
        return try await dbQueue.read { db in
            try Album
                .filter(Album.Columns.normalizedName.like("%\(normalizedQuery)%"))
                .order(Album.Columns.title)
                .fetchAll(db)
        }
    }
    
    /// Search artists using normalized name for better matching
    /// - Parameter query: Search query
    /// - Returns: Array of matching artists
    func searchArtists(query: String) async throws -> [Artist] {
        let normalizedQuery = query.normalized
        
        return try await dbQueue.read { db in
            try Artist
                .filter(Artist.Columns.normalizedName.like("%\(normalizedQuery)%"))
                .order(Artist.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Search genres using normalized name for better matching
    /// - Parameter query: Search query
    /// - Returns: Array of matching genres
    func searchGenres(query: String) async throws -> [Genre] {
        let normalizedQuery = query.normalized
        
        return try await dbQueue.read { db in
            try Genre
                .filter(Genre.Columns.normalizedName.like("%\(normalizedQuery)%"))
                .order(Genre.Columns.name)
                .fetchAll(db)
        }
    }
    
    // MARK: - Entity Retrieval Helpers
    
    /// Get album ID by title and artist
    /// - Parameters:
    ///   - title: Album title
    ///   - artist: Artist name
    /// - Returns: Album ID if found, nil otherwise
    func getAlbumId(title: String, artist: String) async throws -> Int64? {
        let normalizedTitle = title.normalized
        
        return try await dbQueue.read { db in
            try Album
                .filter(Album.Columns.normalizedName == normalizedTitle)
                .fetchOne(db)?.id
        }
    }
    
    /// Get artist ID by name
    /// - Parameter name: Artist name
    /// - Returns: Artist ID if found, nil otherwise
    func getArtistId(name: String) async throws -> Int64? {
        let normalizedName = name.normalized
        
        return try await dbQueue.read { db in
            try Artist
                .filter(Artist.Columns.normalizedName == normalizedName)
                .fetchOne(db)?.id
        }
    }
    
    /// Get album by ID
    /// - Parameter albumId: Album ID
    /// - Returns: Album object
    func getAlbum(albumId: Int64) async throws -> Album {
        return try await dbQueue.read { db in
            guard let album = try Album.fetchOne(db, key: albumId) else {
                throw DatabaseError.recordNotFound(table: "albums", id: albumId)
            }
            return album
        }
    }
    
    /// Get artist by ID
    /// - Parameter artistId: Artist ID
    /// - Returns: Artist object
    func getArtist(artistId: Int64) async throws -> Artist {
        return try await dbQueue.read { db in
            guard let artist = try Artist.fetchOne(db, key: artistId) else {
                throw DatabaseError.recordNotFound(table: "artists", id: artistId)
            }
            return artist
        }
    }

    
    // MARK: - Playlist Operations
    
    /// Get all playlists, sorted by name
    func getAllPlaylists() async throws -> [Playlist] {
        return try await dbQueue.read { db in
            try Playlist
                .order(Playlist.Columns.name)
                .fetchAll(db)
        }
    }
    
    /// Search playlists by name
    /// - Parameter query: Search query
    /// - Returns: Array of matching playlists
    func searchPlaylists(query: String) async throws -> [Playlist] {
        guard !query.isEmpty else {
            return try await getAllPlaylists()
        }
        
        let pattern = "%\(query)%"
        return try await dbQueue.read { db in
            try Playlist
                .filter(Playlist.Columns.name.like(pattern))
                .order(Playlist.Columns.name)
                .fetchAll(db)
        }
    }
}

