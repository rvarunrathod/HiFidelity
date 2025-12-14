//
//  M3UPlaylistHandler.swift
//  HiFidelity
//
//  M3U Playlist Import/Export Handler
//

import Foundation

/// Handler for M3U playlist file format
struct M3UPlaylistHandler {
    
    // MARK: - Import
    
    /// Import tracks from an M3U playlist file
    /// - Parameter url: URL to the M3U file
    /// - Returns: Tuple containing playlist name and array of valid track file paths
    static func importM3U(from url: URL) throws -> (name: String, trackPaths: [URL]) {
        let content = try String(contentsOf: url, encoding: .utf8)
        let playlistName = url.deletingPathExtension().lastPathComponent
        
        var trackPaths: [URL] = []
        let lines = content.components(separatedBy: .newlines)
        
        let baseDirectory = url.deletingLastPathComponent()
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines, comments (except #EXTM3U), and metadata
            guard !trimmedLine.isEmpty,
                  !trimmedLine.hasPrefix("#EXTM3U"),
                  !trimmedLine.hasPrefix("#EXTINF:"),
                  !trimmedLine.hasPrefix("#EXTGRP:"),
                  !trimmedLine.hasPrefix("#PLAYLIST:") else {
                continue
            }
            
            // Parse file path
            let fileURL: URL
            
            if trimmedLine.hasPrefix("file://") {
                // Absolute file URL
                fileURL = URL(string: trimmedLine) ?? URL(fileURLWithPath: trimmedLine.replacingOccurrences(of: "file://", with: ""))
            } else if trimmedLine.hasPrefix("/") || trimmedLine.contains(":\\") {
                // Absolute path (Unix or Windows style)
                fileURL = URL(fileURLWithPath: trimmedLine)
            } else {
                // Relative path - resolve relative to M3U file location
                fileURL = baseDirectory.appendingPathComponent(trimmedLine)
            }
            
            // Check if file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                trackPaths.append(fileURL)
                Logger.debug("M3U Import: Found track - \(fileURL.lastPathComponent)")
            } else {
                Logger.warning("M3U Import: File not found - \(fileURL.path)")
            }
        }
        
        Logger.info("M3U Import: Successfully loaded \(trackPaths.count) tracks from \(playlistName)")
        
        return (name: playlistName, trackPaths: trackPaths)
    }
    
    // MARK: - Export
    
    /// Export tracks to an M3U playlist file
    /// - Parameters:
    ///   - tracks: Array of tracks to export
    ///   - playlistName: Name of the playlist
    ///   - url: URL where to save the M3U file
    ///   - useRelativePaths: Whether to use relative paths (default: false, uses absolute paths)
    static func exportM3U(tracks: [Track], playlistName: String, to url: URL, useRelativePaths: Bool = false) throws {
        var content = "#EXTM3U\n"
        content += "#PLAYLIST:\(playlistName)\n\n"
        
        let baseDirectory = url.deletingLastPathComponent()
        
        for track in tracks {
            // Add extended info (duration and track info)
            let durationInSeconds = Int(track.duration)
            content += "#EXTINF:\(durationInSeconds),\(track.artist) - \(track.title)\n"
            
            // Add file path
            let trackPath: String
            if useRelativePaths {
                // Try to create relative path
                trackPath = relativePath(from: baseDirectory, to: track.url) ?? track.url.path
            } else {
                // Use absolute path
                trackPath = track.url.path
            }
            
            content += "\(trackPath)\n"
        }
        
        // Write to file
        try content.write(to: url, atomically: true, encoding: .utf8)
        
        Logger.info("M3U Export: Successfully exported \(tracks.count) tracks to \(url.lastPathComponent)")
    }
    
    // MARK: - Helper Methods
    
    /// Calculate relative path from one URL to another
    private static func relativePath(from baseURL: URL, to targetURL: URL) -> String? {
        // Get path components
        let baseComponents = baseURL.standardized.pathComponents
        let targetComponents = targetURL.standardized.pathComponents
        
        // Find common prefix
        var commonLength = 0
        for (base, target) in zip(baseComponents, targetComponents) {
            if base == target {
                commonLength += 1
            } else {
                break
            }
        }
        
        // If no common path, return nil (can't create relative path)
        guard commonLength > 0 else {
            return nil
        }
        
        // Build relative path
        let upLevels = baseComponents.count - commonLength
        var relativeComponents: [String] = Array(repeating: "..", count: upLevels)
        relativeComponents.append(contentsOf: targetComponents[commonLength...])
        
        return relativeComponents.joined(separator: "/")
    }
}

