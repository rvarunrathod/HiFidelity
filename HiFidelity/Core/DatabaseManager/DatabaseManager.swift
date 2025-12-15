//
//  Database.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/10/25.
//

//
// DatabaseManager class
//
// This class handles all the Database operations done by the app, note that this file only
// contains core methods, the domain-specific logic is spread across extension files within this
// directory where each file is prefixed with `DM`.
//

import Foundation
import GRDB

class DatabaseManager: ObservableObject {
    // MARK: - Properties
//    @Published var isScanning: Bool = false
//    @Published var scanStatusMessage: String = ""

    let dbQueue: DatabaseQueue
    private let dbPath: String

    // MARK: - Initialization
    
    // MARK: - Singleton
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            Logger.critical("Failed to initialize database: \(error)")
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    // Make init private to prevent multiple instances
    private init() throws {
        // Create database in app support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        // Use bundle identifier as the folder name
        let bundleID = Bundle.main.bundleIdentifier ?? About.bundleIdentifier
        let appDirectory = appSupport.appendingPathComponent(bundleID, isDirectory: true)

        // Create directory if it doesn't exist
        try FileManager.default.createDirectory(at: appDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        let dbFilename = bundleID.hasSuffix(".debug") ?  "\(About.bundleName)-debug.db" : "\(About.bundleName).db"
        dbPath = appDirectory.appendingPathComponent(dbFilename).path
        Logger.info("Database path: \(dbPath)")

        // Configure database before creating the queue
        var config = Configuration()
        config.prepareDatabase { db in
            // Set journal mode to WAL
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Enable synchronous mode for better durability
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            // Set a reasonable busy timeout
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        // Initialize database queue with configuration
        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Use migration system for both new and existing databases
        try DatabaseMigrator.migrate(dbQueue)
    }

    // MARK: - Database Maintenance

    func checkpoint() {
        do {
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            Logger.info("WAL checkpoint completed")
        } catch {
            Logger.error("WAL checkpoint failed: \(error)")
        }
    }

    // MARK: - Migration Status
    
    /// Check if database needs migration
    func needsMigration() -> Bool {
        DatabaseMigrator.hasUnappliedMigrations(dbQueue)
    }
    
    /// Get list of applied migrations
    func getAppliedMigrations() -> [String] {
        DatabaseMigrator.appliedMigrations(dbQueue)
    }

    // MARK: - Helper Methods

    /// Clean up database file and recreate schema
    /// Warning: This will delete all data!
    func resetDatabase() throws {
        // Erase the database
        try dbQueue.erase()
        
        // Re-run migrations on the fresh database
        try DatabaseMigrator.migrate(dbQueue)
        
        Logger.info("Database reset completed")
    }
    
    /// Get database file size in bytes
    func getDatabaseSize() -> Int64? {
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfItem(atPath: dbPath)
            return attributes[.size] as? Int64
        } catch {
            Logger.error("Failed to get database size: \(error)")
            return nil
        }
    }
    
    /// Vacuum the database to reclaim space
    func vacuumDatabase() async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
        Logger.info("Database vacuum completed")
    }
    
    /// Rebuild FTS5 virtual tables to refresh search indexes
    /// This is useful after data corruption or to apply new FTS configurations
    func rebuildFTS() async throws {
        Logger.info("Rebuilding FTS5 virtual tables...")
        
        try await dbQueue.write { db in
            // Rebuild each FTS table using FTS5's rebuild command
            // This repopulates the index from the content tables
            try db.execute(sql: "INSERT INTO tracks_fts(tracks_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO albums_fts(albums_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO artists_fts(artists_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO genres_fts(genres_fts) VALUES('rebuild')")
            try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('rebuild')")
            
            // Optimize FTS tables after rebuild for better performance
            try db.execute(sql: "INSERT INTO tracks_fts(tracks_fts) VALUES('optimize')")
            try db.execute(sql: "INSERT INTO albums_fts(albums_fts) VALUES('optimize')")
            try db.execute(sql: "INSERT INTO artists_fts(artists_fts) VALUES('optimize')")
            try db.execute(sql: "INSERT INTO genres_fts(genres_fts) VALUES('optimize')")
            try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('optimize')")
        }
        
        Logger.info("FTS5 rebuild completed successfully")
    }
    
    /// Upgrade FTS5 tables with enhanced configuration (used in migrations)
    /// This drops existing FTS tables and recreates them with new tokenization settings
    static func upgradeFTSTables(in db: Database) throws {
        Logger.info("Upgrading FTS5 tables with enhanced tokenization...")
        
        // Drop old FTS tables and their triggers
        try db.execute(sql: "DROP TABLE IF EXISTS tracks_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS albums_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS artists_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS genres_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS playlists_fts")
        
        // Drop old triggers
        let triggersToDrop = [
            "tracks_fts_insert", "tracks_fts_delete", "tracks_fts_update",
            "albums_fts_insert", "albums_fts_delete", "albums_fts_update",
            "artists_fts_insert", "artists_fts_delete", "artists_fts_update",
            "genres_fts_insert", "genres_fts_delete", "genres_fts_update",
            "playlists_fts_insert", "playlists_fts_delete", "playlists_fts_update"
        ]
        
        for trigger in triggersToDrop {
            try db.execute(sql: "DROP TRIGGER IF EXISTS \(trigger)")
        }
        
        // Recreate with enhanced configuration
        try createFTSTables(in: db)
        
        // Rebuild FTS tables with existing data from content tables
        Logger.info("Rebuilding FTS5 indexes from existing data...")
        
        // Use FTS5's 'rebuild' command to repopulate from content tables
        try db.execute(sql: "INSERT INTO tracks_fts(tracks_fts) VALUES('rebuild')")
        try db.execute(sql: "INSERT INTO albums_fts(albums_fts) VALUES('rebuild')")
        try db.execute(sql: "INSERT INTO artists_fts(artists_fts) VALUES('rebuild')")
        try db.execute(sql: "INSERT INTO genres_fts(genres_fts) VALUES('rebuild')")
        try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('rebuild')")
        
        // Optimize FTS tables for better query performance
        try db.execute(sql: "INSERT INTO tracks_fts(tracks_fts) VALUES('optimize')")
        try db.execute(sql: "INSERT INTO albums_fts(albums_fts) VALUES('optimize')")
        try db.execute(sql: "INSERT INTO artists_fts(artists_fts) VALUES('optimize')")
        try db.execute(sql: "INSERT INTO genres_fts(genres_fts) VALUES('optimize')")
        try db.execute(sql: "INSERT INTO playlists_fts(playlists_fts) VALUES('optimize')")
        
        Logger.info("FTS5 tables upgraded and rebuilt successfully")
    }
}

// MARK: - Local Enums


enum DatabaseError: Error {
    case invalidTrackId
    case invalidFolderId
    case updateFailed
    case migrationFailed(String)
    case scanFailed(String)
    case trackNotFound(id: Int64)
    case fileNotFound(path: String)
    case lyricsNotFound(trackId: Int64)
    case recordNotFound(table: String, id: Int64)
    case duplicateTrackInPlaylist
    
    var localizedDescription: String {
        switch self {
        case .invalidTrackId:
            return "Invalid track ID"
        case .invalidFolderId:
            return "Invalid folder ID"
        case .updateFailed:
            return "Failed to update database"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .scanFailed(let message):
            return "Scan failed: \(message)"
        case .trackNotFound(let id):
            return "Track with ID \(id) not found"
        case .fileNotFound(let path):
            return "File not found at path: \(path)"
        case .lyricsNotFound(let trackId):
            return "No lyrics found for track ID \(trackId)"
        case .recordNotFound(let table, let id):
            return "Record not found in table '\(table)' with ID \(id)"
        case .duplicateTrackInPlaylist:
            return "Track already exists in this playlist"
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return self.filter { element in
            guard !seen.contains(element) else { return false }
            seen.insert(element)
            return true
        }
    }
}
