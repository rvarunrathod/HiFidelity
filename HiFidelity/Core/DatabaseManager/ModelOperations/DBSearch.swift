//
//  DBSearch.swift
//  HiFidelity
//
//  Full-text search operations across all entities
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Search Mode
    
    enum SearchMode {
        case or   // Match ANY word (broader results)
        case and  // Match ALL words (exact/strict results)
    }
    
    // MARK: - Unified Search Results
    
    struct SearchResults {
        var tracks: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var genres: [Genre] = []
        var playlists: [Playlist] = []
        
        var isEmpty: Bool {
            tracks.isEmpty && albums.isEmpty && artists.isEmpty && genres.isEmpty && playlists.isEmpty
        }
        
        var totalCount: Int {
            tracks.count + albums.count + artists.count + genres.count + playlists.count
        }
    }
    
    // MARK: - Full-Text Search (FTS5)
    
    /// Perform full-text search across all entities using FTS5 with advanced ranking
    /// - Parameters:
    ///   - query: Search query string (supports FTS5 syntax)
    ///   - limit: Maximum results per category (default: 50)
    ///   - mode: Search mode - .or (match any word) or .and (match all words)
    /// - Returns: SearchResults containing matches from all categories, ranked by relevance
    func search(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults()
        }
        
        // Prepare FTS5 queries with different strategies
        let queries = prepareFTSQueries(query, mode: mode)
        
        do {
            return try await dbQueue.read { db in
                var results = SearchResults()
                
                // Search tracks with weighted columns (title > artist > album > genre)
                // BM25 ranking: title=10.0, artist=5.0, album=3.0, album_artist=3.0, genre=1.0, composer=1.0
                results.tracks = try searchTracksWeighted(db: db, queries: queries, limit: limit)
                
                // Search albums with weighted columns (title > normalized_name > album_artist)
                // BM25 ranking: title=10.0, normalized_name=5.0, album_artist=3.0
                results.albums = try searchAlbumsWeighted(db: db, queries: queries, limit: limit)
                
                // Search artists with weighted columns (name > normalized_name)
                // BM25 ranking: name=10.0, normalized_name=5.0
                results.artists = try searchArtistsWeighted(db: db, queries: queries, limit: limit)
                
                // Search genres with weighted columns (name > normalized_name)
                // BM25 ranking: name=10.0, normalized_name=5.0
                results.genres = try searchGenresWeighted(db: db, queries: queries, limit: limit)
                
                // Search playlists with weighted columns (name > description)
                // BM25 ranking: name=10.0, description=2.0
                results.playlists = try searchPlaylistsWeighted(db: db, queries: queries, limit: limit)
                
                return results
            }
        } catch {
            // Log FTS5 errors for debugging but return empty results instead of crashing
            Logger.error("FTS5 search error for query '\(query)': \(error)")
            return SearchResults()
        }
    }
    
    // MARK: - Weighted Search Helpers
    
    private func searchTracksWeighted(db: Database, queries: SearchQueries, limit: Int) throws -> [Track] {
        // Multi-tier search: exact phrase → weighted prefix → fuzzy
        var trackIdScores: [(id: Int64, score: Double)] = []
        
        // Tier 1: Exact phrase match (highest priority)
        if let exactQuery = queries.exactPhrase {
            do {
                let exactResults = try Row.fetchAll(db, sql: """
                    SELECT id, bm25(tracks_fts, 10.0, 5.0, 3.0, 3.0, 1.0, 1.0) as score
                    FROM tracks_fts
                    WHERE tracks_fts MATCH ?
                    ORDER BY score
                    LIMIT ?
                """, arguments: [exactQuery, limit])
                
                for row in exactResults {
                    let id: Int64 = row["id"]
                    let score: Double = row["score"]
                    trackIdScores.append((id, score * 100.0)) // Boost exact matches significantly
                }
            } catch {
                Logger.warning("Exact phrase search failed for tracks: \(error)")
                // Continue with weighted search
            }
        }
        
        // Tier 2: Weighted prefix/term match
        do {
            let prefixResults = try Row.fetchAll(db, sql: """
                SELECT id, bm25(tracks_fts, 10.0, 5.0, 3.0, 3.0, 1.0, 1.0) as score
                FROM tracks_fts
                WHERE tracks_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """, arguments: [queries.weighted, limit * 2])
            
            for row in prefixResults {
                let id: Int64 = row["id"]
                let score: Double = row["score"]
                // Don't add duplicates from exact match
                if !trackIdScores.contains(where: { $0.id == id }) {
                    trackIdScores.append((id, score))
                }
            }
        } catch {
            Logger.error("Weighted search failed for tracks: \(error)")
            return []
        }
        
        // Sort by combined score and get top results
        trackIdScores.sort { $0.score < $1.score } // BM25 returns negative scores, lower is better
        let topIds = Array(trackIdScores.prefix(limit)).map { $0.id }
        
        guard !topIds.isEmpty else { return [] }
        
        // Fetch tracks maintaining order
        let tracks = try Track.filter(topIds.contains(Track.Columns.trackId)).fetchAll(db)
        return topIds.compactMap { id in tracks.first { $0.trackId == id } }
    }
    
    private func searchAlbumsWeighted(db: Database, queries: SearchQueries, limit: Int) throws -> [Album] {
        var albumIdScores: [(id: Int64, score: Double)] = []
        
        // Exact phrase match
        if let exactQuery = queries.exactPhrase {
            do {
                let exactResults = try Row.fetchAll(db, sql: """
                    SELECT id, bm25(albums_fts, 10.0, 5.0, 3.0) as score
                    FROM albums_fts
                    WHERE albums_fts MATCH ?
                    ORDER BY score
                    LIMIT ?
                """, arguments: [exactQuery, limit])
                
                for row in exactResults {
                    albumIdScores.append((row["id"], row["score"] * 100.0))
                }
            } catch {
                Logger.warning("Exact phrase search failed for albums: \(error)")
            }
        }
        
        // Weighted prefix match
        do {
            let prefixResults = try Row.fetchAll(db, sql: """
                SELECT id, bm25(albums_fts, 10.0, 5.0, 3.0) as score
                FROM albums_fts
                WHERE albums_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """, arguments: [queries.weighted, limit * 2])
            
            for row in prefixResults {
                let id: Int64 = row["id"]
                if !albumIdScores.contains(where: { $0.id == id }) {
                    albumIdScores.append((id, row["score"]))
                }
            }
        } catch {
            Logger.error("Weighted search failed for albums: \(error)")
            return []
        }
        
        albumIdScores.sort { $0.score < $1.score }
        let topIds = Array(albumIdScores.prefix(limit)).map { $0.id }
        
        guard !topIds.isEmpty else { return [] }
        
        let albums = try Album.filter(topIds.contains(Album.Columns.id)).fetchAll(db)
        return topIds.compactMap { id in albums.first { $0.id == id } }
    }
    
    private func searchArtistsWeighted(db: Database, queries: SearchQueries, limit: Int) throws -> [Artist] {
        var artistIdScores: [(id: Int64, score: Double)] = []
        
        if let exactQuery = queries.exactPhrase {
            do {
                let exactResults = try Row.fetchAll(db, sql: """
                    SELECT id, bm25(artists_fts, 10.0, 5.0) as score
                    FROM artists_fts
                    WHERE artists_fts MATCH ?
                    ORDER BY score
                    LIMIT ?
                """, arguments: [exactQuery, limit])
                
                for row in exactResults {
                    artistIdScores.append((row["id"], row["score"] * 100.0))
                }
            } catch {
                Logger.warning("Exact phrase search failed for artists: \(error)")
            }
        }
        
        do {
            let prefixResults = try Row.fetchAll(db, sql: """
                SELECT id, bm25(artists_fts, 10.0, 5.0) as score
                FROM artists_fts
                WHERE artists_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """, arguments: [queries.weighted, limit * 2])
            
            for row in prefixResults {
                let id: Int64 = row["id"]
                if !artistIdScores.contains(where: { $0.id == id }) {
                    artistIdScores.append((id, row["score"]))
                }
            }
        } catch {
            Logger.error("Weighted search failed for artists: \(error)")
            return []
        }
        
        artistIdScores.sort { $0.score < $1.score }
        let topIds = Array(artistIdScores.prefix(limit)).map { $0.id }
        
        guard !topIds.isEmpty else { return [] }
        
        let artists = try Artist.filter(topIds.contains(Artist.Columns.id)).fetchAll(db)
        return topIds.compactMap { id in artists.first { $0.id == id } }
    }
    
    private func searchGenresWeighted(db: Database, queries: SearchQueries, limit: Int) throws -> [Genre] {
        var genreIdScores: [(id: Int64, score: Double)] = []
        
        if let exactQuery = queries.exactPhrase {
            do {
                let exactResults = try Row.fetchAll(db, sql: """
                    SELECT id, bm25(genres_fts, 10.0, 5.0) as score
                    FROM genres_fts
                    WHERE genres_fts MATCH ?
                    ORDER BY score
                    LIMIT ?
                """, arguments: [exactQuery, limit])
                
                for row in exactResults {
                    genreIdScores.append((row["id"], row["score"] * 100.0))
                }
            } catch {
                Logger.warning("Exact phrase search failed for genres: \(error)")
            }
        }
        
        do {
            let prefixResults = try Row.fetchAll(db, sql: """
                SELECT id, bm25(genres_fts, 10.0, 5.0) as score
                FROM genres_fts
                WHERE genres_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """, arguments: [queries.weighted, limit * 2])
            
            for row in prefixResults {
                let id: Int64 = row["id"]
                if !genreIdScores.contains(where: { $0.id == id }) {
                    genreIdScores.append((id, row["score"]))
                }
            }
        } catch {
            Logger.error("Weighted search failed for genres: \(error)")
            return []
        }
        
        genreIdScores.sort { $0.score < $1.score }
        let topIds = Array(genreIdScores.prefix(limit)).map { $0.id }
        
        guard !topIds.isEmpty else { return [] }
        
        let genres = try Genre.filter(topIds.contains(Genre.Columns.id)).fetchAll(db)
        return topIds.compactMap { id in genres.first { $0.id == id } }
    }
    
    private func searchPlaylistsWeighted(db: Database, queries: SearchQueries, limit: Int) throws -> [Playlist] {
        var playlistIdScores: [(id: Int64, score: Double)] = []
        
        if let exactQuery = queries.exactPhrase {
            do {
                let exactResults = try Row.fetchAll(db, sql: """
                    SELECT id, bm25(playlists_fts, 10.0, 2.0) as score
                    FROM playlists_fts
                    WHERE playlists_fts MATCH ?
                    ORDER BY score
                    LIMIT ?
                """, arguments: [exactQuery, limit])
                
                for row in exactResults {
                    playlistIdScores.append((row["id"], row["score"] * 100.0))
                }
            } catch {
                Logger.warning("Exact phrase search failed for playlists: \(error)")
            }
        }
        
        do {
            let prefixResults = try Row.fetchAll(db, sql: """
                SELECT id, bm25(playlists_fts, 10.0, 2.0) as score
                FROM playlists_fts
                WHERE playlists_fts MATCH ?
                ORDER BY score
                LIMIT ?
            """, arguments: [queries.weighted, limit * 2])
            
            for row in prefixResults {
                let id: Int64 = row["id"]
                if !playlistIdScores.contains(where: { $0.id == id }) {
                    playlistIdScores.append((id, row["score"]))
                }
            }
        } catch {
            Logger.error("Weighted search failed for playlists: \(error)")
            return []
        }
        
        playlistIdScores.sort { $0.score < $1.score }
        let topIds = Array(playlistIdScores.prefix(limit)).map { $0.id }
        
        guard !topIds.isEmpty else { return [] }
        
        let playlists = try Playlist
            .filter(topIds.contains(Playlist.Columns.id))
            .filter(Playlist.Columns.isSmart == false)
            .fetchAll(db)
        return topIds.compactMap { id in playlists.first { $0.id == id } }
    }
    
    /// Container for different FTS5 query strategies
    private struct SearchQueries {
        let weighted: String      // Main weighted query with prefix matching
        let exactPhrase: String?  // Exact phrase match (if applicable)
    }
    
    /// Prepare advanced FTS5 queries with multiple strategies
    /// - Parameters:
    ///   - query: Raw search query from user
    ///   - mode: Search mode - .or (match any word) or .and (match all words)
    /// - Returns: SearchQueries with different query strategies
    private func prepareFTSQueries(_ query: String, mode: SearchMode = .and) -> SearchQueries {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return SearchQueries(weighted: "\"__no_match__\"", exactPhrase: nil)
        }
        
        // Detect quoted phrases for exact matching
        var exactPhrase: String? = nil
        var workingQuery = trimmed
        
        // Check if query is wrapped in quotes
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
            let phrase = String(trimmed.dropFirst().dropLast())
            let sanitizedPhrase = sanitizeForFTS(phrase)
            if !sanitizedPhrase.isEmpty {
                exactPhrase = "\"\(sanitizedPhrase)\""
            }
            workingQuery = phrase
        }
        
        // Sanitize and split into terms
        let sanitized = sanitizeForFTS(workingQuery)
        
        // After sanitization, check if we have anything left
        guard !sanitized.isEmpty else {
            return SearchQueries(weighted: "\"__no_match__\"", exactPhrase: nil)
        }
        
        let terms = sanitized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        guard !terms.isEmpty else {
            return SearchQueries(weighted: "\"__no_match__\"", exactPhrase: nil)
        }
        
        // Build weighted query with prefix matching
        let ftsTerms = terms.map { term -> String in
            if term.count < 2 {
                // Very short terms: exact match only
                return "\"\(term)\""
            } else if term.count < 3 {
                // Short terms: quoted with prefix
                return "\"\(term)\"*"
            } else {
                // Standard terms: prefix matching for fuzzy results
                return "\(term)*"
            }
        }
        
        // Build weighted query based on mode
        let weightedQuery: String
        switch mode {
        case .or:
            // OR mode: broader results, any term matches
            weightedQuery = ftsTerms.joined(separator: " OR ")
        case .and:
            // AND mode: stricter results, all terms must match
            // Use implicit AND (space) for better performance
            weightedQuery = ftsTerms.joined(separator: " ")
        }
        
        return SearchQueries(
            weighted: weightedQuery,
            exactPhrase: exactPhrase
        )
    }
    
    /// Sanitize query string by removing FTS5 special characters
    private func sanitizeForFTS(_ query: String) -> String {
        return query
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")  // Remove apostrophes
            .replacingOccurrences(of: "`", with: "")  // Remove backticks
            .replacingOccurrences(of: ".", with: "")  // Remove periods (for acronyms like B.Y.O.B)
            .replacingOccurrences(of: ",", with: "")  // Remove commas
            .replacingOccurrences(of: ";", with: "")  // Remove semicolons
            .replacingOccurrences(of: "!", with: "")  // Remove exclamation marks
            .replacingOccurrences(of: "?", with: "")  // Remove question marks
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "-", with: " ") // Replace hyphens with spaces
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "/", with: " ") // Replace slashes with spaces
            .replacingOccurrences(of: "\\", with: " ") // Replace backslashes with spaces
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Category-Specific Search (FTS5)
    
    /// Search tracks only using FTS5 with weighted ranking
    func searchTracks(query: String, limit: Int = 100, mode: SearchMode = .and) async throws -> [Track] {
        guard !query.isEmpty else { return [] }
        
        let queries = prepareFTSQueries(query, mode: mode)
        
        return try await dbQueue.read { db in
            return try searchTracksWeighted(db: db, queries: queries, limit: limit)
        }
    }
    
    /// Search albums only using FTS5 with weighted ranking
    func searchAlbums(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Album] {
        guard !query.isEmpty else { return [] }
        
        let queries = prepareFTSQueries(query, mode: mode)
        
        return try await dbQueue.read { db in
            return try searchAlbumsWeighted(db: db, queries: queries, limit: limit)
        }
    }
    
    /// Search artists only using FTS5 with weighted ranking
    func searchArtists(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Artist] {
        guard !query.isEmpty else { return [] }
        
        let queries = prepareFTSQueries(query, mode: mode)
        
        return try await dbQueue.read { db in
            return try searchArtistsWeighted(db: db, queries: queries, limit: limit)
        }
    }
    
    /// Search genres only using FTS5 with weighted ranking
    func searchGenres(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Genre] {
        guard !query.isEmpty else { return [] }
        
        let queries = prepareFTSQueries(query, mode: mode)
        
        return try await dbQueue.read { db in
            return try searchGenresWeighted(db: db, queries: queries, limit: limit)
        }
    }
    
    /// Search playlists only using FTS5 with weighted ranking
    func searchPlaylists(query: String, limit: Int = 50, mode: SearchMode = .and) async throws -> [Playlist] {
        guard !query.isEmpty else { return [] }
        
        let queries = prepareFTSQueries(query, mode: mode)
        
        return try await dbQueue.read { db in
            return try searchPlaylistsWeighted(db: db, queries: queries, limit: limit)
        }
    }
}

