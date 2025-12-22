//
//  Track.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/10/25.
//

import Foundation
import GRDB

struct Track: Identifiable, Equatable, Hashable, FetchableRecord, MutablePersistableRecord {
    let id = UUID()
    var trackId: Int64?
    let url: URL
    
    // Core metadata for display
    var title: String
    var artist: String
    var album: String
    var duration: Double
    
    // File properties
    let format: String
    var folderId: Int64?
    
    // Navigation fields (for "Go to" functionality)
    var albumArtist: String?
    var composer: String
    var genre: String
    var year: String
    
    // User interaction state
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date?
    var rating: Int?
    
    // Sorting fields
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    
    // Additional metadata
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    
    // Sort fields
    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?
    
    // Audio properties
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    
    // File properties
    var fileSize: Int64?
    var dateModified: Date?
    
    // State tracking
    var isMetadataLoaded: Bool = false
    var isDuplicate: Bool = false
    var dateAdded: Date?
    var primaryTrackId: Int64?
    var duplicateGroupId: String?
    
    // Foreign key references to normalized entities
    var albumId: Int64?
    var artistId: Int64?
    var genreId: Int64?
    
    var artworkData: Data?
    private static var artworkCache = NSCache<NSString, NSData>()
    
    
    // Extended metadata stored as JSON
    var extendedMetadata: ExtendedMetadata?
    
    // R128 Loudness Analysis (for volume normalization)
    var r128IntegratedLoudness: Double? // in LUFS
    
    var filename: String {
        url.lastPathComponent
    }
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        
        // Default values - these will be overridden by metadata
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.composer = "Unknown Composer"
        self.genre = "Unknown Genre"
        self.year = "Unknown Year"
        self.duration = 0
        self.format = url.pathExtension
    }
    
    // MARK: - DB Configuration
    
    static let databaseTableName = "tracks"
    
    enum Columns {
        static let trackId = Column("id")
        static let folderId = Column("folder_id")
        static let path = Column("path")
        static let filename = Column("filename")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let rating = Column("rating")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let totalTracks = Column("total_tracks")
        static let discNumber = Column("disc_number")
        static let totalDiscs = Column("total_discs")
        static let compilation = Column("compilation")
        static let releaseDate = Column("release_date")
        static let originalReleaseDate = Column("original_release_date")
        static let bpm = Column("bpm")
        static let mediaType = Column("media_type")
        static let sortTitle = Column("sort_title")
        static let sortArtist = Column("sort_artist")
        static let sortAlbum = Column("sort_album")
        static let sortAlbumArtist = Column("sort_album_artist")
        static let bitrate = Column("bitrate")
        static let sampleRate = Column("sample_rate")
        static let channels = Column("channels")
        static let codec = Column("codec")
        static let bitDepth = Column("bit_depth")
        static let fileSize = Column("file_size")
        static let isDuplicate = Column("is_duplicate")
        static let primaryTrackId = Column("primary_track_id")
        static let duplicateGroupId = Column("duplicate_group_id")
        static let artworkData = Column("artwork_data")
        static let extendedMetadata = Column("extended_metadata")
        static let albumId = Column("album_id")
        static let artistId = Column("artist_id")
        static let genreId = Column("genre_id")
        static let r128IntegratedLoudness = Column("r128_integrated_loudness")
    }
    
    static let columnMap: [String: Column] = [
        "artist": Columns.artist,
        "album": Columns.album,
        "album_artist": Columns.albumArtist,
        "composer": Columns.composer,
        "genre": Columns.genre,
        "year": Columns.year
    ]
    
    // MARK: - FetchableRecord
    
    init(row: GRDB.Row) throws {
        // Extract path and create URL
        let path: String = row[Columns.path]
        self.url = URL(fileURLWithPath: path)
        
        // Core properties
        trackId = row[Columns.trackId]
        title = row[Columns.title]
        artist = row[Columns.artist]
        album = row[Columns.album]
        duration = row[Columns.duration]
        
        self.format = row[Columns.format]
        folderId = row[Columns.folderId]
        
        // Navigation fields
        albumArtist = row[Columns.albumArtist]
        composer = row[Columns.composer]
        genre = row[Columns.genre]
        year = row[Columns.year]
        
        // User interaction
        isFavorite = row[Columns.isFavorite]
        playCount = row[Columns.playCount]
        lastPlayedDate = row[Columns.lastPlayedDate]
        rating = row[Columns.rating]
        
        // Sorting fields
        trackNumber = row[Columns.trackNumber]
        totalTracks = row[Columns.totalTracks]
        discNumber = row[Columns.discNumber]
        totalDiscs = row[Columns.totalDiscs]
        
        // Additional metadata
        compilation = row[Columns.compilation] ?? false
        releaseDate = row[Columns.releaseDate]
        originalReleaseDate = row[Columns.originalReleaseDate]
        bpm = row[Columns.bpm]
        mediaType = row[Columns.mediaType]
        
        // Sort fields
        sortTitle = row[Columns.sortTitle]
        sortArtist = row[Columns.sortArtist]
        sortAlbum = row[Columns.sortAlbum]
        sortAlbumArtist = row[Columns.sortAlbumArtist]
        
        // Audio properties
        bitrate = row[Columns.bitrate]
        sampleRate = row[Columns.sampleRate]
        channels = row[Columns.channels]
        codec = row[Columns.codec]
        bitDepth = row[Columns.bitDepth]
        
        // File properties
        fileSize = row[Columns.fileSize]
        dateModified = row[Columns.dateModified]
        
        // State tracking
        isMetadataLoaded = true
        dateAdded = row[Columns.dateAdded]
        isDuplicate = row[Columns.isDuplicate] ?? false
        primaryTrackId = row[Columns.primaryTrackId]
        duplicateGroupId = row[Columns.duplicateGroupId]
        
        artworkData = row[Columns.artworkData]
        
        // Extended metadata (JSON)
        if let jsonString: String = row[Columns.extendedMetadata] {
            extendedMetadata = ExtendedMetadata.fromJSON(jsonString)
        }
        
        // Foreign key references
        albumId = row[Columns.albumId]
        artistId = row[Columns.artistId]
        genreId = row[Columns.genreId]
        
        // R128 Loudness
        r128IntegratedLoudness = row[Columns.r128IntegratedLoudness]
    }
    
    // MARK: - PersistableRecord
    
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.trackId] = trackId
        container[Columns.path] = url.path
        container[Columns.filename] = filename
        
        // Core metadata
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.duration] = duration
        
        container[Columns.format] = format
        container[Columns.folderId] = folderId
        
        // Navigation fields
        container[Columns.albumArtist] = albumArtist
        container[Columns.composer] = composer
        container[Columns.genre] = genre
        container[Columns.year] = year
        
        // User interaction
        container[Columns.isFavorite] = isFavorite
        container[Columns.playCount] = playCount
        container[Columns.lastPlayedDate] = lastPlayedDate
        container[Columns.rating] = rating
        
        // Sorting fields
        container[Columns.trackNumber] = trackNumber
        container[Columns.totalTracks] = totalTracks
        container[Columns.discNumber] = discNumber
        container[Columns.totalDiscs] = totalDiscs
        
        // Additional metadata
        container[Columns.compilation] = compilation
        container[Columns.releaseDate] = releaseDate
        container[Columns.originalReleaseDate] = originalReleaseDate
        container[Columns.bpm] = bpm
        container[Columns.mediaType] = mediaType
        
        // Sort fields
        container[Columns.sortTitle] = sortTitle
        container[Columns.sortArtist] = sortArtist
        container[Columns.sortAlbum] = sortAlbum
        container[Columns.sortAlbumArtist] = sortAlbumArtist
        
        // Audio properties
        container[Columns.bitrate] = bitrate
        container[Columns.sampleRate] = sampleRate
        container[Columns.channels] = channels
        container[Columns.codec] = codec
        container[Columns.bitDepth] = bitDepth
        
        // File properties
        container[Columns.fileSize] = fileSize
        container[Columns.dateModified] = dateModified

        // State tracking
        container[Columns.dateAdded] = dateAdded ?? Date()
        container[Columns.isDuplicate] = isDuplicate
        container[Columns.primaryTrackId] = primaryTrackId
        container[Columns.duplicateGroupId] = duplicateGroupId
        
        container[Columns.artworkData] = artworkData
        
        // Extended metadata (stored as JSON)
        container[Columns.extendedMetadata] = extendedMetadata?.toJSON()
        
        // Foreign key references
        container[Columns.albumId] = albumId
        container[Columns.artistId] = artistId
        container[Columns.genreId] = genreId
        
        // R128 Loudness
        container[Columns.r128IntegratedLoudness] = r128IntegratedLoudness
    }
    
    // Auto-incrementing id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        trackId = inserted.rowID
    }
    
    // MARK: - Relationships
    
    // Folder relationship
    static let folder = belongsTo(Folder.self)
    var folder: QueryInterfaceRequest<Folder> {
        request(for: Track.folder)
    }
    
    // Normalized entity relationships 
    static let albumEntity = belongsTo(Album.self, key: "album")
    var albumEntity: QueryInterfaceRequest<Album> {
        request(for: Track.albumEntity)
    }
    
    static let artistEntity = belongsTo(Artist.self, key: "artist")
    var artistEntity: QueryInterfaceRequest<Artist> {
        request(for: Track.artistEntity)
    }
    
    static let genreEntity = belongsTo(Genre.self, key: "genre")
    var genreEntity: QueryInterfaceRequest<Genre> {
        request(for: Track.genreEntity)
    }
    
    // Playlist relationship (many-to-many through junction table)
    static let playlistTracks = hasMany(PlaylistTrack.self)
    static let playlists = hasMany(Playlist.self, through: playlistTracks, using: PlaylistTrack.playlist)
    
    // MARK: - Equatable
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
}



// MARK: - Helper Methods

extension Track {
    /// Get a display-friendly artist name
    var displayArtist: String {
        albumArtist ?? artist
    }
    
    /// Get formatted duration string
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Check if this track has album artwork
    var hasArtwork: Bool {
        artworkData != nil
    }
}

// MARK: - Update Helpers

extension Track {
    /// Create a copy with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> Track {
        var copy = self
        copy.isFavorite = isFavorite
        return copy
    }
    
    /// Create a copy with updated play stats
    func withPlayStats(playCount: Int, lastPlayedDate: Date?) -> Track {
        var copy = self
        copy.playCount = playCount
        copy.lastPlayedDate = lastPlayedDate
        return copy
    }
}

// MARK: - Duplicate Detection

extension Track {
    /// Generate a key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
}


// MARK: - Database Query Helpers

extension Track {
    /// Fetch only the columns needed for lightweight Track
    /// NOTE: Excludes artworkData to avoid loading large blobs into memory
    /// Use ArtworkCache to load artwork on-demand
    static var lightweightSelection: [Column] {
        [
            Columns.trackId,
            Columns.folderId,
            Columns.path,
            Columns.filename,
            Columns.title,
            Columns.artist,
            Columns.album,
            Columns.composer,
            Columns.genre,
            Columns.year,
            Columns.duration,
            Columns.format,
            Columns.dateAdded,
            Columns.dateModified,
            Columns.isFavorite,
            Columns.playCount,
            Columns.lastPlayedDate,
            Columns.trackNumber,
            Columns.discNumber,
            Columns.isDuplicate,
            Columns.fileSize,
            Columns.codec,
            Columns.albumId,
            Columns.artistId,
            Columns.r128IntegratedLoudness
        ]
    }
    
    /// Request for fetching lightweight tracks
    static func lightweightRequest() -> QueryInterfaceRequest<Track> {
        Track
            .select(lightweightSelection)
            .filter(Columns.isDuplicate == false)
    }
}
