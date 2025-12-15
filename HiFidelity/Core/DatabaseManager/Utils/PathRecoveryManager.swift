//
//  PathRecoveryManager.swift
//  HiFidelity
//
//  Handles recovery of moved/missing audio files through multiple strategies
//

import Foundation
import GRDB

/// Manages recovery of tracks when their file paths become invalid
class PathRecoveryManager {
    static let shared = PathRecoveryManager()
    
    // MARK: - Properties
    
    /// Cache of recently recovered paths (old path -> new path)
    private var recoveredPaths: [String: String] = [:]
    
    /// Tracks that failed recovery (to avoid repeated attempts)
    private var failedRecoveryPaths: Set<String> = []
    
    /// Detection of moved folders (old folder path -> new folder path)
    private var movedFolders: [String: String] = [:]
    
    private init() {}
    
    // MARK: - Public API
    
    
    /// Bulk update all tracks from an old folder path to new folder path
    /// Uses a single transaction for atomicity - either all updates succeed or all fail
    func relocateFolder(oldFolderURL: URL, newFolderURL: URL) async throws {
        let oldPath = oldFolderURL.path
        let newPath = newFolderURL.path
        
        Logger.info("Relocating folder: \(oldPath) -> \(newPath)")
        
        // Cache this folder move
        movedFolders[oldPath] = newPath
        
        // Perform all updates in a single transaction
        let (successCount, failCount) = try await DatabaseManager.shared.dbQueue.write { db -> (Int, Int) in
            // Get all tracks in this folder
            let tracks = try Track
                .filter(Track.Columns.path.like("\(oldPath)%"))
                .fetchAll(db)
            
            Logger.info("Found \(tracks.count) tracks to relocate")
            
            var updatedCount = 0
            var failedCount = 0
            
            // Update each track's path
            for track in tracks {
                let relativePath = String(track.url.path.dropFirst(oldPath.count))
                let newTrackPath = newPath + relativePath
                
                // Verify file exists at new location before updating
                if FileManager.default.fileExists(atPath: newTrackPath) {
                    try db.execute(
                        sql: "UPDATE tracks SET path = ? WHERE id = ?",
                        arguments: [newTrackPath, track.trackId]
                    )
                    updatedCount += 1
                } else {
                    Logger.warning("Skipping track - file not found at new location: \(track.filename)")
                    failedCount += 1
                }
            }
            
            // Update folder path in the same transaction
            try db.execute(
                sql: "UPDATE folders SET path = ? WHERE path = ?",
                arguments: [newPath, oldPath]
            )
            
            Logger.info("Transaction: Updated \(updatedCount) tracks and 1 folder")
            
            return (updatedCount, failedCount)
        }
        
        // Cache successful recoveries (after transaction succeeds)
        let tracks = try await DatabaseManager.shared.dbQueue.read { db in
            try Track
                .filter(Track.Columns.path.like("\(newPath)%"))
                .fetchAll(db)
        }
        
        for track in tracks {
            let relativePath = String(track.url.path.dropFirst(newPath.count))
            let oldTrackPath = oldPath + relativePath
            recoveredPaths[oldTrackPath] = track.url.path
        }
        
        Logger.info("Relocation complete: \(successCount) succeeded, \(failCount) failed")
        
        // Notify UI to refresh
        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .foldersDataDidChange, object: nil)
        }
    }
    
    
    
    // MARK: - Helper Methods

    /// Update track path in database
    private func updateTrackPath(_ track: Track, newURL: URL) async {
        guard let trackId = track.trackId else {
            Logger.error("Cannot update path - track has no ID")
            return
        }
        
        do {
            try await DatabaseManager.shared.updateTrackPath(
                trackId: trackId,
                newPath: newURL.path
            )
            
            // Cache this recovery
            recoveredPaths[track.url.path] = newURL.path
            
            Logger.info("Updated track path in database: \(track.filename)")
            
        } catch {
            Logger.error("Failed to update track path: \(error)")
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear recovery cache
    func clearCache() {
        recoveredPaths.removeAll()
        failedRecoveryPaths.removeAll()
        movedFolders.removeAll()
        Logger.info("Cleared path recovery cache")
    }
}


