//
//  RemoteArtworkLoader.swift
//  HiFidelity
//
//  Reimplements `ArtworkCache.loadTrackArtworkWithFallback` (which is
//  `private` to ArtworkCache) for the HTTP artwork route. Reads only;
//  runs off-main on the FlyingFox executor since GRDB's `dbQueue.read`
//  is non-blocking against writers thanks to WAL.
//

import Foundation
import GRDB

enum RemoteArtworkLoader {
    /// Result tuple: raw image bytes + sniffed Content-Type.
    struct ArtworkBytes {
        let data: Data
        let contentType: String
    }

    /// Look up artwork for a track by stable DB row id. Album artwork is
    /// preferred (cheaper, fewer duplicates); falls back to the track's
    /// own embedded artwork. Returns `nil` if neither table has bytes.
    static func data(forTrackId trackId: Int64) throws -> ArtworkBytes? {
        try DatabaseManager.shared.dbQueue.read { db -> ArtworkBytes? in
            // 1. Read the track row to discover both its embedded artwork
            //    and its album_id in a single query.
            guard let trackRow = try Row.fetchOne(
                db,
                sql: "SELECT artwork_data, album_id FROM tracks WHERE id = ?",
                arguments: [trackId]
            ) else {
                return nil
            }

            let trackArtwork: Data? = trackRow["artwork_data"]
            let albumId: Int64? = trackRow["album_id"]

            // 2. Prefer album artwork when present.
            if let albumId = albumId,
               let albumRow = try Row.fetchOne(
                   db,
                   sql: "SELECT artwork_data FROM albums WHERE id = ?",
                   arguments: [albumId]
               ),
               let albumArtwork = albumRow["artwork_data"] as Data?,
               !albumArtwork.isEmpty,
               let mime = sniffContentType(albumArtwork) {
                return ArtworkBytes(data: albumArtwork, contentType: mime)
            }

            // 3. Fall back to the track's own bytes.
            if let trackArtwork, !trackArtwork.isEmpty,
               let mime = sniffContentType(trackArtwork) {
                return ArtworkBytes(data: trackArtwork, contentType: mime)
            }

            return nil
        }
    }

    /// Identify the image format from the first bytes. Mime is not stored
    /// in the database; embedded art arrives as raw bytes from TagLib.
    /// Returns `nil` for unrecognized formats (HEIC, etc.) so the caller
    /// can 404 — browsers refuse to render `application/octet-stream`.
    private static func sniffContentType(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let b0 = data[data.startIndex]
        let b1 = data[data.startIndex + 1]
        let b2 = data[data.startIndex + 2]
        let b3 = data[data.startIndex + 3]
        // JPEG: FF D8 FF ??
        if b0 == 0xFF, b1 == 0xD8, b2 == 0xFF { return "image/jpeg" }
        // PNG: 89 50 4E 47
        if b0 == 0x89, b1 == 0x50, b2 == 0x4E, b3 == 0x47 { return "image/png" }
        // GIF: 47 49 46 38
        if b0 == 0x47, b1 == 0x49, b2 == 0x46, b3 == 0x38 { return "image/gif" }
        // WEBP: 52 49 46 46 ... 57 45 42 50 — only check the RIFF prefix.
        if b0 == 0x52, b1 == 0x49, b2 == 0x46, b3 == 0x46 { return "image/webp" }
        return nil
    }
}
