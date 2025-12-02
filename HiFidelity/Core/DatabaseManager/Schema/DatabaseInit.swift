//
//  DatabaseInit.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/10/25.
//


//
// DatabaseManager class extension
//
// This extension contains methods for setting up database schema and seed initial data.
// Updated to use migration helpers and static methods.
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Complete Schema Setup
    
    /// Create all tables for the application
    /// Called once during initial database setup
    static func createAllTables(in db: Database) throws {
        Logger.info("Creating database schema...")
        
        // Core tables
        try createFoldersTable(in: db)
        try createTracksTable(in: db)
        
        // Normalized entity tables
        try createAlbumsTable(in: db)
        try createArtistsTable(in: db)
        try createGenresTable(in: db)
        
        // Playlist tables
        try createPlaylistsTable(in: db)
        try createPlaylistTracksTable(in: db)
        
        // Queue table
        try createQueueTable(in: db)
        
        // Lyrics table
        try createLyricsTable(in: db)
        
        // Song features table (for ML recommendations)
        try createSongFeaturesTable(in: db)
        
        // Create triggers for automatic orphan cleanup
        try createOrphanCleanupTriggers(in: db)
        
        // Create triggers for statistics updates
        try createStatisticsUpdateTriggers(in: db)
        
        // Create Full-Text Search tables
        try createFTSTables(in: db)
        
        Logger.info("All database tables created successfully")
    }
    
    // MARK: - Full-Text Search Tables
    
    /// Create FTS5 virtual tables for full-text search
    static func createFTSTables(in db: Database) throws {
        Logger.info("Creating FTS5 virtual tables...")
        
        // FTS for tracks - search by title, artist, album, genre
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
                id UNINDEXED,
                title,
                artist,
                album,
                album_artist,
                genre,
                composer,
                content='tracks',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        
        // FTS for albums - search by title, normalized name, and artist
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS albums_fts USING fts5(
                id UNINDEXED,
                title,
                normalized_name,
                album_artist,
                content='albums',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        
        // FTS for artists - search by name and normalized name
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS artists_fts USING fts5(
                id UNINDEXED,
                name,
                normalized_name,
                content='artists',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        
        // FTS for genres - search by name and normalized name
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS genres_fts USING fts5(
                id UNINDEXED,
                name,
                normalized_name,
                content='genres',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        
        // FTS for playlists - search by name and description
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS playlists_fts USING fts5(
                id UNINDEXED,
                name,
                description,
                content='playlists',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)
        
        // Create triggers to keep FTS tables in sync with content tables
        try createFTSTriggers(in: db)
        
        Logger.info("FTS5 virtual tables created successfully")
    }
    
    /// Create triggers to automatically update FTS tables
    static func createFTSTriggers(in db: Database) throws {
        // Tracks FTS triggers
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_insert AFTER INSERT ON tracks BEGIN
                INSERT INTO tracks_fts(rowid, id, title, artist, album, album_artist, genre, composer)
                VALUES (new.id, new.id, new.title, new.artist, new.album, new.album_artist, new.genre, new.composer);
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_delete AFTER DELETE ON tracks BEGIN
                DELETE FROM tracks_fts WHERE rowid = old.id;
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS tracks_fts_update AFTER UPDATE ON tracks BEGIN
                DELETE FROM tracks_fts WHERE rowid = old.id;
                INSERT INTO tracks_fts(rowid, id, title, artist, album, album_artist, genre, composer)
                VALUES (new.id, new.id, new.title, new.artist, new.album, new.album_artist, new.genre, new.composer);
            END;
        """)
        
        // Albums FTS triggers
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS albums_fts_insert AFTER INSERT ON albums BEGIN
                INSERT INTO albums_fts(rowid, id, title, normalized_name, album_artist)
                VALUES (new.id, new.id, new.title, new.normalized_name, new.album_artist);
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS albums_fts_delete AFTER DELETE ON albums BEGIN
                DELETE FROM albums_fts WHERE rowid = old.id;
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS albums_fts_update AFTER UPDATE ON albums BEGIN
                DELETE FROM albums_fts WHERE rowid = old.id;
                INSERT INTO albums_fts(rowid, id, title, normalized_name, album_artist)
                VALUES (new.id, new.id, new.title, new.normalized_name, new.album_artist);
            END;
        """)
        
        // Artists FTS triggers
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS artists_fts_insert AFTER INSERT ON artists BEGIN
                INSERT INTO artists_fts(rowid, id, name, normalized_name)
                VALUES (new.id, new.id, new.name, new.normalized_name);
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS artists_fts_delete AFTER DELETE ON artists BEGIN
                DELETE FROM artists_fts WHERE rowid = old.id;
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS artists_fts_update AFTER UPDATE ON artists BEGIN
                DELETE FROM artists_fts WHERE rowid = old.id;
                INSERT INTO artists_fts(rowid, id, name, normalized_name)
                VALUES (new.id, new.id, new.name, new.normalized_name);
            END;
        """)
        
        // Genres FTS triggers
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS genres_fts_insert AFTER INSERT ON genres BEGIN
                INSERT INTO genres_fts(rowid, id, name, normalized_name)
                VALUES (new.id, new.id, new.name, new.normalized_name);
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS genres_fts_delete AFTER DELETE ON genres BEGIN
                DELETE FROM genres_fts WHERE rowid = old.id;
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS genres_fts_update AFTER UPDATE ON genres BEGIN
                DELETE FROM genres_fts WHERE rowid = old.id;
                INSERT INTO genres_fts(rowid, id, name, normalized_name)
                VALUES (new.id, new.id, new.name, new.normalized_name);
            END;
        """)
        
        // Playlists FTS triggers (handle NULL description with COALESCE)
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS playlists_fts_insert AFTER INSERT ON playlists BEGIN
                INSERT INTO playlists_fts(rowid, id, name, description)
                VALUES (new.id, new.id, new.name, COALESCE(new.description, ''));
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS playlists_fts_delete AFTER DELETE ON playlists BEGIN
                DELETE FROM playlists_fts WHERE rowid = old.id;
            END;
        """)
        
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS playlists_fts_update AFTER UPDATE ON playlists BEGIN
                DELETE FROM playlists_fts WHERE rowid = old.id;
                INSERT INTO playlists_fts(rowid, id, name, description)
                VALUES (new.id, new.id, new.name, COALESCE(new.description, ''));
            END;
        """)
        
        Logger.info("FTS triggers created successfully")
    }
    
    // MARK: - Core Tables
    
    static func createTracksTable(in db: Database) throws {
        try db.createTableIfNotExists("tracks") { t in
            
            t.autoIncrementedPrimaryKey("id")
            
            // File identification
            t.column("path", .text).notNull().unique()
            t.column("filename", .text).notNull()
            
            // Core metadata
            t.column("title", .text).notNull()
            t.column("artist", .text).notNull()
            t.column("album", .text).notNull()
            t.column("duration", .double).notNull().check { $0 >= 0 }
            
            // File properties
            t.column("format", .text).notNull()
            t.column("folder_id", .integer).notNull().references("folders", onDelete: .cascade)
            t.column("file_size", .integer)
            t.column("date_modified", .datetime)
            
            // Navigation fields
            t.column("album_artist", .text)
            t.column("composer", .text).notNull()
            t.column("genre", .text).notNull()
            t.column("year", .text).notNull()
            
            // User interaction state
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            t.column("play_count", .integer).notNull().defaults(to: 0)
            t.column("last_played_date", .datetime)
            t.column("rating", .integer).check { $0 == nil || ($0 >= 0 && $0 <= 5) }
            
            // Track/Disc information
            t.column("track_number", .integer)
            t.column("total_tracks", .integer)
            t.column("disc_number", .integer)
            t.column("total_discs", .integer)
            
            // Additional metadata
            t.column("compilation", .boolean).notNull().defaults(to: false)
            t.column("release_date", .text)
            t.column("original_release_date", .text)
            t.column("bpm", .integer)
            t.column("media_type", .text)
            
            // Sort fields
            t.column("sort_title", .text)
            t.column("sort_artist", .text)
            t.column("sort_album", .text)
            t.column("sort_album_artist", .text)
            
            // Audio properties
            t.column("bitrate", .integer)
            t.column("sample_rate", .integer)
            t.column("channels", .integer)
            t.column("codec", .text)
            t.column("bit_depth", .integer)
            
            // Artwork
            t.column("artwork_data", .blob)
            
            // State tracking
            t.column("date_added", .datetime).notNull()
            
            // Duplicate tracking
            t.column("is_duplicate", .boolean).notNull().defaults(to: false)
            t.column("primary_track_id", .integer).references("tracks", column: "id", onDelete: .setNull)
            t.column("duplicate_group_id", .text)
            
            // Extended metadata (JSON)
            t.column("extended_metadata", .text)
            
            // Foreign keys to normalized entities (set null on delete to preserve track data)
            t.column("album_id", .integer).references("albums", column: "id", onDelete: .setNull, onUpdate: .cascade)
            t.column("artist_id", .integer).references("artists", column: "id", onDelete: .setNull, onUpdate: .cascade)
            t.column("genre_id", .integer).references("genres", column: "id", onDelete: .setNull, onUpdate: .cascade)
        }
        
        // Create indexes on foreign keys
        try db.create(index: "idx_tracks_album", on: "tracks", columns: ["album_id"], ifNotExists: true)
        try db.create(index: "idx_tracks_artist", on: "tracks", columns: ["artist_id"], ifNotExists: true)
        try db.create(index: "idx_tracks_genre", on: "tracks", columns: ["genre_id"], ifNotExists: true)
        
        Logger.info("Created `tracks` table with indexes")
    }
    
    // MARK: - 1. Folders Table
    
    static func createFoldersTable(in db: Database) throws {
        try db.createTableIfNotExists("folders") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("path", .text).notNull().unique()
            t.column("track_count", .integer).notNull().defaults(to: 0)
            t.column("date_added", .datetime).notNull()
            t.column("date_updated", .datetime).notNull()
            t.column("bookmark_data", .blob)
        }
        Logger.info("Created `folders` table")
    }
    
    // MARK: - Normalized Entity Tables
    
    // MARK: - 3. Albums Table
    
    static func createAlbumsTable(in db: Database) throws {
        try db.create(table: "albums", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Core info (from TagLib metadata)
            t.column("title", .text).notNull()
            t.column("normalized_name", .text).notNull()  // For searching and deduplication
            t.column("sort_name", .text).notNull()        // For proper alphabetical sorting
            t.column("album_artist", .text)
            t.column("year", .text)
            
            // Professional music player fields (HIGH PRIORITY)
            t.column("release_type", .text)              // Album, EP, Single, Compilation, Live
            t.column("record_label", .text)              // Record label name
            t.column("disc_count", .integer).notNull().defaults(to: 1)
            t.column("musicbrainz_album_id", .text)      // MusicBrainz Album ID
            
            // Additional release information (MEDIUM PRIORITY)
            t.column("release_date", .text)              // Full date YYYY-MM-DD
            t.column("musicbrainz_release_group_id", .text)
            
            // Extended metadata (LOW PRIORITY)
            t.column("barcode", .text)                   // UPC/EAN barcode
            t.column("catalog_number", .text)            // Catalog/Matrix number
            t.column("release_country", .text)           // ISO country code
            
            // Aggregated from tracks
            t.column("track_count", .integer).notNull().defaults(to: 0)
            t.column("total_duration", .double).notNull().defaults(to: 0)
            
            // Flags (from TagLib)
            t.column("is_compilation", .boolean).notNull().defaults(to: false)
            
            // Artwork (from TagLib)
            t.column("artwork_data", .blob)
            
            // Timestamps
            t.column("date_added", .datetime).notNull()
            
            // Unique constraint using normalized name for deduplication
            t.uniqueKey(["normalized_name", "album_artist", "year"])
        }
        
        // Indexes for performance
        try db.create(index: "idx_albums_normalized", on: "albums", columns: ["normalized_name"], ifNotExists: true)
        try db.create(index: "idx_albums_sort", on: "albums", columns: ["sort_name"], ifNotExists: true)
        try db.create(index: "idx_albums_artist", on: "albums", columns: ["album_artist"], ifNotExists: true)
        try db.create(index: "idx_albums_release_type", on: "albums", columns: ["release_type"], ifNotExists: true)
        try db.create(index: "idx_albums_musicbrainz", on: "albums", columns: ["musicbrainz_album_id"], ifNotExists: true)
        try db.create(index: "idx_albums_label", on: "albums", columns: ["record_label"], ifNotExists: true)
        
        Logger.info("Created `albums` table with indexes")
    }
    
    // MARK: - 4. Artists Table
    
    static func createArtistsTable(in db: Database) throws {
        try db.create(table: "artists", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Core info (from TagLib metadata)
            t.column("name", .text).notNull()
            t.column("normalized_name", .text).notNull().unique()  // For searching and deduplication
            t.column("sort_name", .text).notNull()                 // For proper alphabetical sorting
            
            // Professional music player fields (HIGH PRIORITY)
            t.column("musicbrainz_artist_id", .text)               // MusicBrainz Artist ID
            t.column("artist_type", .text)                         // Person, Group, Orchestra, Choir
            
            // Extended metadata (MEDIUM PRIORITY)
            t.column("country", .text)                             // ISO country code
            
            // Aggregated from tracks
            t.column("track_count", .integer).notNull().defaults(to: 0)
            t.column("album_count", .integer).notNull().defaults(to: 0)
            
            // Artwork (from tracks)
            t.column("artwork_data", .blob)
            t.column("artwork_source_type", .text)  // "album", "track", or "custom"
            
            // Timestamps
            t.column("date_added", .datetime).notNull()
        }
        
        // Indexes
        try db.create(index: "idx_artists_normalized", on: "artists", columns: ["normalized_name"], ifNotExists: true)
        try db.create(index: "idx_artists_sort", on: "artists", columns: ["sort_name"], ifNotExists: true)
        try db.create(index: "idx_artists_musicbrainz", on: "artists", columns: ["musicbrainz_artist_id"], ifNotExists: true)
        try db.create(index: "idx_artists_type", on: "artists", columns: ["artist_type"], ifNotExists: true)
        
        Logger.info("Created `artists` table with indexes")
    }
    
    // MARK: - 5. Genres Table
    
    static func createGenresTable(in db: Database) throws {
        try db.create(table: "genres", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Core info (from TagLib metadata)
            t.column("name", .text).notNull()
            t.column("normalized_name", .text).notNull().unique()  // For searching and deduplication
            t.column("sort_name", .text).notNull()                 // For proper alphabetical sorting
            
            // Professional music player fields (MEDIUM PRIORITY)
            t.column("style", .text)                               // Sub-genre or style
            
            // Aggregated from tracks
            t.column("track_count", .integer).notNull().defaults(to: 0)
            
            // Timestamps
            t.column("date_added", .datetime).notNull()
        }
        
        // Indexes
        try db.create(index: "idx_genres_normalized", on: "genres", columns: ["normalized_name"], ifNotExists: true)
        try db.create(index: "idx_genres_sort", on: "genres", columns: ["sort_name"], ifNotExists: true)
        
        Logger.info("Created `genres` table with indexes")
    }
    
    // MARK: - Playlist Tables
    
    // MARK: - 6. Playlists Table
    
    static func createPlaylistsTable(in db: Database) throws {
        try db.create(table: "playlists", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Basic info
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("created_date", .datetime).notNull()
            t.column("modified_date", .datetime).notNull()
            
            // Metadata
            t.column("track_count", .integer).notNull().defaults(to: 0)
            t.column("total_duration", .double).notNull().defaults(to: 0)
            
            // Artwork
            t.column("custom_artwork_data", .blob)
            t.column("color_scheme", .text) // JSON: dominant colors
            
            // Organization
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            
            
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            
            // Smart playlist flag
            t.column("is_smart", .boolean).notNull().defaults(to: false)
            
            // Play stats
            t.column("date_last_played", .datetime)
            t.column("play_count", .integer).notNull().defaults(to: 0)
        }
        
        // Indexes
        try db.create(index: "idx_playlists_name", on: "playlists", columns: ["name"], ifNotExists: true)
        try db.create(index: "idx_playlists_is_smart", on: "playlists", columns: ["is_smart"], ifNotExists: true)
        
        Logger.info("Created `playlists` table with self-referencing relationships")
    }
    
    // MARK: - 7. Playlist Tracks (Junction Table)
    
    static func createPlaylistTracksTable(in db: Database) throws {
        try db.create(table: "playlist_tracks", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Foreign keys with CASCADE delete
            // When playlist is deleted, remove all its tracks
            t.column("playlist_id", .integer)
                .notNull()
                .indexed()
                .references("playlists", column: "id", onDelete: .cascade, onUpdate: .cascade)
            
            // When track is deleted, remove it from all playlists
            t.column("track_id", .integer)
                .notNull()
                .indexed()
                .references("tracks", column: "id", onDelete: .cascade, onUpdate: .cascade)
            
            // Ordering within playlist
            t.column("position", .integer).notNull()
            
            // Timestamp
            t.column("date_added", .datetime).notNull()
            
            // Composite unique constraint: same track can appear multiple times but not at same position
            t.uniqueKey(["playlist_id", "position"])
        }
        
        // Indexes for fast queries
        try db.create(index: "idx_playlist_tracks_playlist",
                      on: "playlist_tracks",
                      columns: ["playlist_id"],
                      ifNotExists: true)
        
        try db.create(index: "idx_playlist_tracks_track",
                      on: "playlist_tracks",
                      columns: ["track_id"],
                      ifNotExists: true)
        
        try db.create(index: "idx_playlist_tracks_position",
                      on: "playlist_tracks",
                      columns: ["playlist_id", "position"],
                      ifNotExists: true)
        
        Logger.info("Created `playlist_tracks` junction table with CASCADE rules")
    }
    
    // MARK: - Queue Table
    
    // MARK: - 8. Queue Table
    
    static func createQueueTable(in db: Database) throws {
        try db.create(table: "queue", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Foreign key to tracks
            // CASCADE: deleting track removes it from queue
            t.column("track_id", .integer)
                .notNull()
                .references("tracks", column: "id", onDelete: .cascade, onUpdate: .cascade)
            
            // Queue position
            t.column("position", .integer).notNull().indexed()
                        
            // Unique position
            t.uniqueKey(["position"])
        }
        
        // Indexes
        try db.create(index: "idx_queue_position",
                      on: "queue",
                      columns: ["position"],
                      ifNotExists: true)
        
        try db.create(index: "idx_queue_track",
                      on: "queue",
                      columns: ["track_id"],
                      ifNotExists: true)
        
        Logger.info("Created `queue` table with CASCADE rules and indexes")
    }
    
    // MARK: - Lyrics Table
    
    // MARK: - 9. Lyrics Table
    
    static func createLyricsTable(in db: Database) throws {
        try db.create(table: "lyrics", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Foreign key to tracks
            // CASCADE: deleting track removes its lyrics
            t.column("track_id", .integer)
                .notNull()
                .references("tracks", column: "id", onDelete: .cascade, onUpdate: .cascade)
            
            // LRC content (can be large)
            t.column("lrc_content", .text).notNull()
            
            // Language code (ISO 639-1: en, es, ja, etc.)
            t.column("language", .text)
            
            // Source of lyrics (user, api, embedded, etc.)
            t.column("source", .text)
            
            // Timestamps
            t.column("date_added", .datetime).notNull()
            t.column("date_modified", .datetime).notNull()
        }
        
        // Indexes for fast queries
        try db.create(index: "idx_lyrics_track",
                      on: "lyrics",
                      columns: ["track_id"],
                      ifNotExists: true)
        
        try db.create(index: "idx_lyrics_track_language",
                      on: "lyrics",
                      columns: ["track_id", "language"],
                      ifNotExists: true)
        
        Logger.info("Created `lyrics` table with CASCADE rules and indexes")
    }
    
    // MARK: - Song Features Table
    
    /// Create song_features table for ML-based recommendations
    /// Stores extracted audio features and embeddings for each track
    static func createSongFeaturesTable(in db: Database) throws {
        try db.create(table: "song_features", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            
            // Foreign key to tracks - CASCADE on delete
            t.column("track_id", .integer)
                .notNull()
                .unique()
                .references("tracks", column: "id", onDelete: .cascade, onUpdate: .cascade)
            
            // MARK: - Audio Features (0.0 to 1.0 normalized)
            
            /// Tempo in BPM
            t.column("tempo", .double)
            
            /// Energy level (intensity and activity)
            t.column("energy", .double)
            
            /// Valence (musical positiveness/happiness)
            t.column("valence", .double)
            
            /// Danceability (how suitable for dancing)
            t.column("danceability", .double)
            
            /// Acousticness (acoustic vs electronic)
            t.column("acousticness", .double)
            
            /// Instrumentalness (likelihood of no vocals)
            t.column("instrumentalness", .double)
            
            /// Liveness (presence of audience)
            t.column("liveness", .double)
            
            /// Speechiness (presence of spoken words)
            t.column("speechiness", .double)
            
            /// Loudness in dB
            t.column("loudness", .double)
            
            /// Musical key (0-11: C, C#, D, etc.)
            t.column("key", .integer)
            
            /// Mode (0 = minor, 1 = major)
            t.column("mode", .integer)
            
            /// Time signature
            t.column("time_signature", .integer)
            
            /// Musical mood (enum stored as text)
            t.column("mood", .text)
            
            // MARK: - Spectral Features
            
            /// Spectral centroid (brightness)
            t.column("spectral_centroid", .double)
            
            /// Spectral rolloff
            t.column("spectral_rolloff", .double)
            
            /// Zero crossing rate (noisiness)
            t.column("zero_crossing_rate", .double)
            
            // MARK: - Embedding Vector
            
            /// High-dimensional feature embedding (stored as JSON)
            /// Example: OpenL3, VGGish, MFCC embeddings
            t.column("embedding", .text)
            
            /// Embedding model version/type
            t.column("embedding_model", .text)
            
            /// Dimensionality of embedding
            t.column("embedding_dimension", .integer)
            
            // MARK: - Metadata
            
            /// When features were extracted
            t.column("extracted_at", .datetime).notNull()
            
            /// Version of feature extraction algorithm
            t.column("extractor_version", .text)
            
            /// Confidence score of extraction (0.0 to 1.0)
            t.column("confidence", .double)
            
            /// Whether features need re-extraction
            t.column("needs_update", .boolean).notNull().defaults(to: false)
        }
        
        // Indexes for efficient querying
        try db.create(index: "idx_song_features_track",
                      on: "song_features",
                      columns: ["track_id"],
                      unique: true,
                      ifNotExists: true)
        
        // Index for finding tracks needing feature extraction
        try db.create(index: "idx_song_features_needs_update",
                      on: "song_features",
                      columns: ["needs_update"],
                      ifNotExists: true)
        
        // Indexes for feature-based queries
        try db.create(index: "idx_song_features_energy",
                      on: "song_features",
                      columns: ["energy"],
                      ifNotExists: true)
        
        try db.create(index: "idx_song_features_valence",
                      on: "song_features",
                      columns: ["valence"],
                      ifNotExists: true)
        
        try db.create(index: "idx_song_features_danceability",
                      on: "song_features",
                      columns: ["danceability"],
                      ifNotExists: true)
        
        try db.create(index: "idx_song_features_tempo",
                      on: "song_features",
                      columns: ["tempo"],
                      ifNotExists: true)
        
        try db.create(index: "idx_song_features_mood",
                      on: "song_features",
                      columns: ["mood"],
                      ifNotExists: true)
        
        Logger.info("Created `song_features` table with CASCADE rules and feature indexes")
    }
    
    // MARK: - Database Triggers
    
    /// Create statistics update triggers for albums, artists, and genres
    /// These triggers automatically update track counts and other statistics when tracks are added, removed, or modified
    static func createStatisticsUpdateTriggers(in db: Database) throws {
        // Trigger: Update album statistics when track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_album_stats_on_delete
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.album_id IS NOT NULL
            BEGIN
                UPDATE albums
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE album_id = OLD.album_id
                    ),
                    total_duration = (
                        SELECT COALESCE(SUM(duration), 0) FROM tracks WHERE album_id = OLD.album_id
                    )
                WHERE id = OLD.album_id;
            END;
        """)
        
        // Trigger: Update artist statistics when track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_artist_stats_on_delete
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.artist_id IS NOT NULL
            BEGIN
                UPDATE artists
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE artist_id = OLD.artist_id
                    ),
                    album_count = (
                        SELECT COUNT(DISTINCT album_id) FROM tracks 
                        WHERE artist_id = OLD.artist_id AND album_id IS NOT NULL
                    )
                WHERE id = OLD.artist_id;
            END;
        """)
        
        // Trigger: Update genre statistics when track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_genre_stats_on_delete
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.genre_id IS NOT NULL
            BEGIN
                UPDATE genres
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE genre_id = OLD.genre_id
                    )
                WHERE id = OLD.genre_id;
            END;
        """)
        
        // Trigger: Update album statistics when track is inserted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_album_stats_on_insert
            AFTER INSERT ON tracks
            FOR EACH ROW
            WHEN NEW.album_id IS NOT NULL
            BEGIN
                UPDATE albums
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE album_id = NEW.album_id
                    ),
                    total_duration = (
                        SELECT COALESCE(SUM(duration), 0) FROM tracks WHERE album_id = NEW.album_id
                    )
                WHERE id = NEW.album_id;
            END;
        """)
        
        // Trigger: Update artist statistics when track is inserted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_artist_stats_on_insert
            AFTER INSERT ON tracks
            FOR EACH ROW
            WHEN NEW.artist_id IS NOT NULL
            BEGIN
                UPDATE artists
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE artist_id = NEW.artist_id
                    ),
                    album_count = (
                        SELECT COUNT(DISTINCT album_id) FROM tracks 
                        WHERE artist_id = NEW.artist_id AND album_id IS NOT NULL
                    )
                WHERE id = NEW.artist_id;
            END;
        """)
        
        // Trigger: Update genre statistics when track is inserted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_genre_stats_on_insert
            AFTER INSERT ON tracks
            FOR EACH ROW
            WHEN NEW.genre_id IS NOT NULL
            BEGIN
                UPDATE genres
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE genre_id = NEW.genre_id
                    )
                WHERE id = NEW.genre_id;
            END;
        """)
        
        // Trigger: Update album statistics when track's album changes
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_album_stats_on_update
            AFTER UPDATE OF album_id, duration ON tracks
            FOR EACH ROW
            WHEN OLD.album_id IS NOT NEW.album_id OR OLD.duration != NEW.duration
            BEGIN
                -- Update old album statistics (if it exists)
                UPDATE albums
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE album_id = OLD.album_id
                    ),
                    total_duration = (
                        SELECT COALESCE(SUM(duration), 0) FROM tracks WHERE album_id = OLD.album_id
                    )
                WHERE id = OLD.album_id AND OLD.album_id IS NOT NULL;
                
                -- Update new album statistics (if it exists)
                UPDATE albums
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE album_id = NEW.album_id
                    ),
                    total_duration = (
                        SELECT COALESCE(SUM(duration), 0) FROM tracks WHERE album_id = NEW.album_id
                    )
                WHERE id = NEW.album_id AND NEW.album_id IS NOT NULL;
            END;
        """)
        
        // Trigger: Update artist statistics when track's artist changes
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_artist_stats_on_update
            AFTER UPDATE OF artist_id, album_id ON tracks
            FOR EACH ROW
            WHEN OLD.artist_id IS NOT NEW.artist_id
            BEGIN
                -- Update old artist statistics (if it exists)
                UPDATE artists
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE artist_id = OLD.artist_id
                    ),
                    album_count = (
                        SELECT COUNT(DISTINCT album_id) FROM tracks 
                        WHERE artist_id = OLD.artist_id AND album_id IS NOT NULL
                    )
                WHERE id = OLD.artist_id AND OLD.artist_id IS NOT NULL;
                
                -- Update new artist statistics (if it exists)
                UPDATE artists
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE artist_id = NEW.artist_id
                    ),
                    album_count = (
                        SELECT COUNT(DISTINCT album_id) FROM tracks 
                        WHERE artist_id = NEW.artist_id AND album_id IS NOT NULL
                    )
                WHERE id = NEW.artist_id AND NEW.artist_id IS NOT NULL;
            END;
        """)
        
        // Trigger: Update genre statistics when track's genre changes
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS update_genre_stats_on_update
            AFTER UPDATE OF genre_id ON tracks
            FOR EACH ROW
            WHEN OLD.genre_id IS NOT NEW.genre_id
            BEGIN
                -- Update old genre statistics (if it exists)
                UPDATE genres
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE genre_id = OLD.genre_id
                    )
                WHERE id = OLD.genre_id AND OLD.genre_id IS NOT NULL;
                
                -- Update new genre statistics (if it exists)
                UPDATE genres
                SET track_count = (
                        SELECT COUNT(*) FROM tracks WHERE genre_id = NEW.genre_id
                    )
                WHERE id = NEW.genre_id AND NEW.genre_id IS NOT NULL;
            END;
        """)
        
        Logger.info("Created statistics update triggers")
    }
    
    /// Create triggers to automatically delete orphaned albums, artists, and genres
    /// These triggers fire after track deletion and clean up entities with no remaining tracks
    static func createOrphanCleanupTriggers(in db: Database) throws {
        
        // Trigger: Delete album if its last track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS cleanup_orphaned_albums
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.album_id IS NOT NULL
            BEGIN
                DELETE FROM albums
                WHERE id = OLD.album_id
                AND NOT EXISTS (
                    SELECT 1 FROM tracks WHERE album_id = OLD.album_id
                );
            END;
        """)
        
        // Trigger: Delete artist if its last track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS cleanup_orphaned_artists
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.artist_id IS NOT NULL
            BEGIN
                DELETE FROM artists
                WHERE id = OLD.artist_id
                AND NOT EXISTS (
                    SELECT 1 FROM tracks WHERE artist_id = OLD.artist_id
                );
            END;
        """)
        
        // Trigger: Delete genre if its last track is deleted
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS cleanup_orphaned_genres
            AFTER DELETE ON tracks
            FOR EACH ROW
            WHEN OLD.genre_id IS NOT NULL
            BEGIN
                DELETE FROM genres
                WHERE id = OLD.genre_id
                AND NOT EXISTS (
                    SELECT 1 FROM tracks WHERE genre_id = OLD.genre_id
                );
            END;
        """)
        
        Logger.info("Created automatic orphan cleanup triggers")
    }
    
    // MARK: - Instance Methods
    
    func setupDatabase() throws {
        try dbQueue.write { db in
            try DatabaseManager.createAllTables(in: db)
        }
    }
}
