//
//  DBFolder.swift
//  HiFidelity
//
//  Created by Varun Rathod on 30/10/25.
//

import Foundation
import AppKit
import GRDB

extension DatabaseManager {
    
    // MARK: - Folder DB operations
    
    func updateFolderTrackCount(_ folder: Folder) async throws {
        try await dbQueue.write { db in
            let count = try Track
                .filter(Track.Columns.folderId == folder.id)
                .fetchCount(db)

            var updatedFolder = folder
            updatedFolder.trackCount = count
            updatedFolder.dateUpdated = Date()
            try updatedFolder.update(db)
        }
    }
    
    func updateFolderMetadata(_ folderId: Int64) async throws {
        let folderData = try await dbQueue.read { db in
            try Folder.fetchOne(db, key: folderId)
        }
        
        guard folderData != nil else { return }
        
        try await dbQueue.write { db in
            guard var folder = try Folder.fetchOne(db, key: folderId) else { return }
            
            // Get and store the file system's modification date
            if let attributes = try? FileManager.default.attributesOfItem(atPath: folder.url.path),
               let fsModDate = attributes[.modificationDate] as? Date {
                folder.dateUpdated = fsModDate
            } else {
                // Fallback to current date if we can't get FS date
                folder.dateUpdated = Date()
            }
            
            
            // Update track count
            let trackCount = try Track
                .filter(Track.Columns.folderId == folderId)
                .filter(Track.Columns.isDuplicate == false)
                .fetchCount(db)
            folder.trackCount = trackCount
            
            try folder.update(db)
        }
    }
    
    func updateFolderBookmark(_ folderId: Int64, bookmarkData: Data) async throws {
        _ = try await dbQueue.write { db in
            try Folder
                .filter(Folder.Columns.id == folderId)
                .updateAll(db, Folder.Columns.bookmarkData.set(to: bookmarkData))
        }
    }
    
    // MARK: - Remove Folders
    
    /// Remove a folder and all its tracks (orphaned entities auto-cleaned by database triggers)
    /// - Parameter folder: Folder to remove
    func removeFolder(_ folder: Folder) async throws {
        guard let folderId = folder.id else {
            Logger.error("Cannot remove folder without ID")
            return
        }
        
        // Get track count for user notification
        let trackCount = try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.folderId == folderId)
                .fetchCount(db)
        }
        
        // Delete folder (cascade will delete all tracks, triggers will cleanup orphaned entities)
        try await dbQueue.write { db in
            _ = try Folder
                .filter(Folder.Columns.id == folderId)
                .deleteAll(db)
        }
        
        Logger.info("Removed folder '\(folder.name)' with \(trackCount) tracks (orphaned entities auto-cleaned by triggers)")
        
        // Notify UI
        await MainActor.run {
            let message = trackCount == 1
                ? "Removed folder '\(folder.name)' with 1 track"
                : "Removed folder '\(folder.name)' with \(trackCount) tracks"
            NotificationManager.shared.addMessage(.info, message)
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
            
            // Stop monitoring this folder
            FolderWatcherService.shared.stopWatching(folder: folder)
        }
    }
    
    // MARK: - Add Folders
    
    func addFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.prompt = "Add Music Folder"
        openPanel.message = "Select folders containing your music files"

        openPanel.beginSheetModal(for: NSApp.keyWindow!) { [weak self] response in
            guard let self = self, response == .OK else { return }

            var urlsToAdd: [URL] = []
            var bookmarkDataMap: [URL: Data] = [:]

            for url in openPanel.urls {
                // Create security bookmark
                do {
                    let bookmarkData = try url.bookmarkData(options: [.withSecurityScope],
                                                            includingResourceValuesForKeys: nil,
                                                            relativeTo: nil)
                    urlsToAdd.append(url)
                    bookmarkDataMap[url] = bookmarkData
                    Logger.info("Created bookmark for folder - \(url.lastPathComponent) at \(url.path)")
                } catch {
                    Logger.error("Failed to create security bookmark for \(url.path): \(error)")
                }
            }

            // Add folders to database with their bookmarks
            if !urlsToAdd.isEmpty {

                DispatchQueue.global(qos: .background).async {
                    self.addFolders(urlsToAdd, bookmarkDataMap: bookmarkDataMap) { result in
                        switch result {
                        case .success(let dbFolders):
                            Logger.info("Successfully added \(dbFolders.count) folders to database")
                        case .failure(let error):
                            Logger.error("Failed to add folders to database: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    func addFolders(_ urls: [URL], bookmarkDataMap: [URL: Data], completion: @escaping (Result<[Folder], Error>) -> Void) {
        Task {
            do {
                let folders = try await addFoldersAsync(urls, bookmarkDataMap: bookmarkDataMap)
                await MainActor.run {
                    completion(.success(folders))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                    Logger.error("Failed to add folders: \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to add folders")
                }
            }
        }
    }

    func addFoldersAsync(_ urls: [URL], bookmarkDataMap: [URL: Data]) async throws -> [Folder] {
        let addedFolders = try await dbQueue.write { db -> [Folder] in
            var folders: [Folder] = []
            
            for url in urls {
                let bookmarkData = bookmarkDataMap[url]
                var folder = Folder(url: url, bookmarkData: bookmarkData)
                
                // Get the file system modification date
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fsModDate = attributes[.modificationDate] as? Date {
                    folder.dateUpdated = fsModDate
                }

                // Check if folder already exists
                if let existing = try Folder
                    .filter(Folder.Columns.path == url.path)
                    .fetchOne(db) {
                    // Update bookmark data if folder exists
                    var updatedFolder = existing
                    updatedFolder.bookmarkData = bookmarkData
                    try updatedFolder.update(db)
                    Logger.info("Folder already exists: \(existing.name) with ID: \(existing.id ?? -1), updated bookmark")
                } else {
                    // Insert new folder - didInsert() automatically sets the ID
                    try folder.insert(db)
                    
                    // Verify insertion succeeded
                    guard folder.id != nil else {
                        Logger.error("Failed to insert folder: \(folder.name) - ID not set")
                        continue
                    }
                    
                    folders.append(folder)
                    Logger.info("Added new folder: \(folder.name) with ID: \(folder.id ?? -1)")
                }
            }
            
            return folders
        }

        // INSTANT UI UPDATE: Notify observers immediately after folders are added
        await MainActor.run {
            NotificationCenter.default.post(name: .foldersDataDidChange, object: nil)
            
            // Start watching newly added folders if monitoring is enabled
            if FolderWatcherService.shared.isWatching {
                for folder in addedFolders {
                    FolderWatcherService.shared.startWatching(folder: folder)
                }
            }
        }

        // Scan the folders for tracks in background
        if !addedFolders.isEmpty {
            try await addFoldersForTracks(addedFolders)
        }


        return addedFolders
    }

    func addFoldersForTracks(_ folders: [Folder]) async throws {
        let totalFolders = folders.count

        if totalFolders > 0 {
            await MainActor.run {
                NotificationManager.shared.addMessage(.info, "Scanning \(totalFolders) folder\(totalFolders == 1 ? "" : "s")...")
            }
        }

        for folder in folders {
            do {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Started scanning '\(folder.name)' folder.")
                }
                
                try await scanSingleFolder(folder)
                
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Scanning completed for '\(folder.name)' folder.")
                }
            } catch {
                Logger.error("Failed to scan folder \(folder.name): \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to scan folder '\(folder.name)'")
                }
            }
        }

        await MainActor.run {
            NotificationManager.shared.addMessage(.info, "Scan complete")
        }
    }
    
    
    // MARK: - Scan Folder


    func scanSingleFolder(_ folder: Folder) async throws {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: folder.url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            let error = DatabaseError.scanFailed("Unable to access folder contents")
            throw error
        }

        guard let folderId = folder.id else {
            let error = DatabaseError.invalidFolderId
            Logger.error("Folder has no ID")
            throw error
        }

        let scanState = FolderScanState()
        
        // Get existing tracks for this folder to check for updates
        let existingTracks = getTracksForFolder(folderId)
        let existingTracksDict = Dictionary(uniqueKeysWithValues: existingTracks.map { ($0.url, $0) })

        // Collect all music files first - do this synchronously before async context
        var musicFiles: [URL] = []
        var scannedPaths = Set<URL>()

        // Process enumerator synchronously
//        var unsupportedFiles: [(url: URL, extension: String)] = []

        while let fileURL = enumerator.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            
            // Skip files without extensions
            guard !fileExtension.isEmpty else { continue }
            
            if AudioFormat.isSupported(fileExtension) {
                musicFiles.append(fileURL)
                scannedPaths.insert(fileURL)
            }
        }

        // Now we can safely use these in async context
        let totalFiles = musicFiles.count
        let foundPaths = scannedPaths

        let foundPathStrings = Set(foundPaths.map { $0.path })
        let tracksToRemove = existingTracks.filter { !foundPathStrings.contains($0.url.path) }
        let trackIdsToRemove = tracksToRemove.compactMap { $0.trackId }
        
        // Remove tracks (orphaned entities will be automatically cleaned up by database triggers)
        if !trackIdsToRemove.isEmpty {
            let removedCount = trackIdsToRemove.count
            
            // Log tracks to be removed (before deletion)
            for track in tracksToRemove {
                Logger.info("Removing track that no longer exists: \(track.url.lastPathComponent)")
            }
            
            // Delete tracks in batch - database triggers will automatically cleanup orphaned entities and update statistics
            let deletedCount = try await dbQueue.write { db in
                // Delete the tracks (triggers will auto-cleanup orphans and update statistics)
                let deleted = try Track
                    .filter(trackIdsToRemove.contains(Track.Columns.trackId))
                    .deleteAll(db)
                
                // Note: Statistics are automatically updated by database triggers
                // Orphaned entities (albums/artists/genres with no tracks) are auto-deleted by triggers
                
                return deleted
            }
            
            Logger.info("Batch deleted \(deletedCount) tracks from folder '\(folder.name)' (orphaned entities auto-cleaned by triggers)")
            
            // Notify about the cleanup
            await MainActor.run {
                if totalFiles == 0 {
                    NotificationManager.shared.addMessage(.info, "Folder '\(folder.name)' is now empty, removed \(removedCount) tracks")
                } else {
                    let message = removedCount == 1
                        ? "Removed 1 missing track from '\(folder.name)'"
                        : "Removed \(removedCount) missing tracks from '\(folder.name)'"
                    NotificationManager.shared.addMessage(.info, message)
                }
            }
        }
        
        // If no music files found and all tracks removed, we're done
        if totalFiles == 0 {
            try await updateFolderTrackCount(folder)
            return
        }

        // Process music files in batches
        let batchSize = totalFiles > 1000 ? 100 : 50
        let fileBatches = musicFiles.chunked(into: batchSize)
        var batchCounter = 0

        for batch in fileBatches {
            let batchWithFolderId = batch.map { url in (url: url, folderId: folderId) }
            
            do {
                try await processBatch(batchWithFolderId, existingTracks: existingTracksDict)
                await scanState.incrementProcessed(by: batch.count)
                
                let currentProcessed = await scanState.getProcessedCount()
                batchCounter += 1
                
                // Update progress
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Processing: \(currentProcessed)/\(totalFiles) files in \(folder.name)")
                }
                
                // Notify UI every few batches to update track counts in real-time
                if batchCounter % 3 == 0 {
                    // Notify observers to refresh UI
                    await MainActor.run {
                        NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
                    }
                }
            } catch {
                // Track failed files but continue processing
                let failures = batch.map { (url: $0, error: error) }
                await scanState.addFailedFiles(failures)
                Logger.error("Failed to process batch in folder \(folder.name): \(error)")
            }
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .libraryDataDidChange, object: nil)
        }
        
        // Update folder metadata
        if let folderId = folder.id {
            try await updateFolderMetadata(folderId)
        }

        // Get final counts
        let processedCount = await scanState.getProcessedCount()
        let failedFiles = await scanState.getFailedFiles()
        let skippedFiles = await scanState.getSkippedFiles()

        // Report results
        if !failedFiles.isEmpty {
            await MainActor.run {
                let message = failedFiles.count == 1
                    ? "Failed to process 1 file in '\(folder.name)'"
                    : "Failed to process \(failedFiles.count) files in '\(folder.name)'"
                NotificationManager.shared.addMessage(.warning, message)
            }
        }
        
        // Report skipped files
        if !skippedFiles.isEmpty {
            let extensionCounts = Dictionary(grouping: skippedFiles) { $0.extension }
                .mapValues { $0.count }
                .sorted { $0.value > $1.value }
            
            let topExtensions = extensionCounts.prefix(3)
                .map { ".\($0.key.uppercased()) (\($0.value))" }
                .joined(separator: ", ")
            
            await MainActor.run {
                let message = skippedFiles.count == 1
                    ? "1 file skipped in '\(folder.name)' - unsupported format"
                    : "\(skippedFiles.count) files skipped in '\(folder.name)' - unsupported formats: \(topExtensions)"
                NotificationManager.shared.addMessage(.warning, message)
            }
        }
        
        Logger.info("Completed scanning folder \(folder.name): \(processedCount) processed, \(failedFiles.count) failed, \(skippedFiles.count) skipped")
    }
    
    
    
    
    // MARK: - Refresh Folders
    
    func rescanFolder(_ folder: Folder) async throws {
        // First, ensure we have a valid bookmark
        Task {
            // Refresh bookmark if needed
            if folder.bookmarkData == nil || !folder.url.startAccessingSecurityScopedResource() {
                await refreshBookmarkForFolder(folder)
            }

            // Then proceed with scanning
            await MainActor.run { [weak self] in
                guard let self = self else { return }

                // Delegate to database manager for refresh
                refreshFolder(folder) { result in
                    switch result {
                    case .success:
                        Logger.info("Successfully refreshed folder \(folder.name)")
                    case .failure(let error):
                        Logger.error("Failed to refresh folder \(folder.name): \(error)")
                    }
                }
            }
        }
    }
    
    func refreshFolder(_ folder: Folder, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Refreshing \(folder.name)...")
                }

                // Log the current state
                let trackCountBefore = getTracksForFolder(folder.id ?? -1).count
                Logger.info("Starting refresh for folder \(folder.name) with \(trackCountBefore) tracks")

                // Scan the folder - this will check for metadata updates
                try await scanSingleFolder(folder)

                // Log the result
                let trackCountAfter = getTracksForFolder(folder.id ?? -1).count
                Logger.info("Completed refresh for folder \(folder.name) with \(trackCountAfter) tracks (was \(trackCountBefore))")

                completion(.success(()))
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                    Logger.error("Failed to refresh folder \(folder.name): \(error)")
                    NotificationManager.shared.addMessage(.error, "Failed to refresh folder \(folder.name)")
                }
            }
        }
    }

    
    
    func refreshBookmarkForFolder(_ folder: Folder) async {
        // Only refresh if we can access the folder
        guard FileManager.default.fileExists(atPath: folder.url.path) else {
            Logger.warning("Folder no longer exists at \(folder.url.path)")
            return
        }

        do {
            // Create a fresh bookmark
            let newBookmarkData = try folder.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Update the folder with new bookmark
            var updatedFolder = folder
            updatedFolder.bookmarkData = newBookmarkData

            // Save to database
            try await updateFolderBookmark(folder.id!, bookmarkData: newBookmarkData)

            Logger.info("Successfully refreshed bookmark for \(folder.name)")
        } catch {
            Logger.error("Failed to refresh bookmark for \(folder.name): \(error)")
        }
    }
    
    // MARK: - Folder Path Management
    
    /// Update a folder's path in the database (for relocated folders)
    func updateFolderPath(folderId: Int64, newPath: String, newBookmarkData: Data? = nil) async throws {
        try await dbQueue.write { db in
            var updates: [String] = ["path = ?"]
            var arguments: [DatabaseValueConvertible?] = [newPath]
            
            if let bookmarkData = newBookmarkData {
                updates.append("bookmark_data = ?")
                arguments.append(bookmarkData)
            }
            
            arguments.append(folderId)
            
            let sql = "UPDATE folders SET \(updates.joined(separator: ", ")) WHERE id = ?"
            try db.execute(sql: sql, arguments: StatementArguments(arguments))
        }
        
        Logger.info("Updated folder path for ID \(folderId)")
    }
    
    /// Update folder path by old path (useful for bulk relocations)
    func updateFolderPathByPath(oldPath: String, newPath: String, newBookmarkData: Data? = nil) async throws {
        try await dbQueue.write { db in
            var updates: [String] = ["path = ?"]
            var arguments: [DatabaseValueConvertible?] = [newPath]
            
            if let bookmarkData = newBookmarkData {
                updates.append("bookmark_data = ?")
                arguments.append(bookmarkData)
            }
            
            arguments.append(oldPath)
            
            let sql = "UPDATE folders SET \(updates.joined(separator: ", ")) WHERE path = ?"
            try db.execute(sql: sql, arguments: StatementArguments(arguments))
        }
        
        Logger.info("Updated folder path: \(oldPath) -> \(newPath)")
    }
    
}

// MARK: - Folder Scan State Actor

/// Actor to track folder scanning progress in a thread-safe manner
actor FolderScanState {
    var processedCount = 0
    var failedFiles: [(url: URL, error: Error)] = []
    var skippedFiles: [(url: URL, extension: String)] = []
    
    func incrementProcessed(by count: Int) {
        processedCount += count
    }
    
    func addFailedFiles(_ files: [(url: URL, error: Error)]) {
        failedFiles.append(contentsOf: files)
    }
    
    func addSkippedFiles(_ files: [(url: URL, extension: String)]) {
        skippedFiles.append(contentsOf: files)
    }
    
    func getProcessedCount() -> Int { processedCount }
    func getFailedFiles() -> [(url: URL, error: Error)] { failedFiles }
    func getSkippedFiles() -> [(url: URL, extension: String)] { skippedFiles }
}
