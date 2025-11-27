//
//  LyricsService.swift
//  HiFidelity
//
//  Service for fetching synchronized lyrics from lrclib.net
//  API Documentation: https://lrclib.net/docs
//

import Foundation

// MARK: - Lyrics Service

/// Service for fetching synchronized lyrics from online sources
final class LyricsService {
    
    // MARK: - Singleton
    
    static let shared = LyricsService()
    
    // MARK: - Properties
    
    private let baseURL = "https://lrclib.net/api"
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        
        // Set user agent as recommended by lrclib.net
        config.httpAdditionalHeaders = [
            "User-Agent": "HiFidelity/1.0 (https://github.com/yourusername/hifidelity)"
        ]
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Search for lyrics by track metadata
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    ///   - albumName: Name of the album (optional)
    ///   - duration: Track duration in seconds (optional, helps narrow results)
    /// - Returns: Array of matching lyrics results
    func searchLyrics(
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        duration: Int? = nil
    ) async throws -> [LyricsSearchResult] {
        
        var components = URLComponents(string: "\(baseURL)/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName)
        ]
        
        Logger.info("Searching lyrics: \(trackName) by \(artistName)")
        
        if let albumName = albumName {
            queryItems.append(URLQueryItem(name: "album_name", value: albumName))
            Logger.info("albumName: \(albumName)")
        }
        
        if let duration = duration {
            if duration != 0 {
                queryItems.append(URLQueryItem(name: "duration", value: String(duration)))
            }
            Logger.info("duration: \(duration)")
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw LyricsServiceError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let results = try JSONDecoder().decode([LyricsSearchResult].self, from: data)
            Logger.info("Found \(results.count) lyrics results")
            return results
            
        case 404:
            Logger.info("No lyrics found for: \(trackName) by \(artistName)")
            return []
            
        case 429:
            throw LyricsServiceError.rateLimitExceeded
            
        default:
            Logger.error("Lyrics search failed with status: \(httpResponse.statusCode)")
            throw LyricsServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Get lyrics by specific ID
    /// - Parameter id: Lyrics ID from search results
    /// - Returns: Detailed lyrics result
    func getLyrics(id: Int) async throws -> LyricsSearchResult {
        guard let url = URL(string: "\(baseURL)/get/\(id)") else {
            throw LyricsServiceError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LyricsServiceError.serverError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(LyricsSearchResult.self, from: data)
    }
    
    /// Get lyrics by track metadata (convenience method)
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    ///   - albumName: Name of the album (optional)
    ///   - duration: Track duration in seconds (optional)
    /// - Returns: First matching synced lyrics, or nil if not found
    func getLyrics(
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        duration: Int? = nil
    ) async throws -> LyricsSearchResult? {
        
        var components = URLComponents(string: "\(baseURL)/get")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName)
        ]
        
        if let albumName = albumName {
            queryItems.append(URLQueryItem(name: "album_name", value: albumName))
        }
        
        if let duration = duration {
            queryItems.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw LyricsServiceError.invalidURL
        }
        
        Logger.info("Fetching lyrics: \(trackName) by \(artistName)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let result = try JSONDecoder().decode(LyricsSearchResult.self, from: data)
            if result.syncedLyrics != nil {
                Logger.info("Found synced lyrics for: \(trackName)")
                return result
            } else {
                Logger.info("Found plain lyrics (no sync) for: \(trackName)")
                return result
            }
            
        case 404:
            Logger.info("No lyrics found for: \(trackName) by \(artistName)")
            return nil
            
        case 429:
            throw LyricsServiceError.rateLimitExceeded
            
        default:
            throw LyricsServiceError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Data Models

/// Lyrics search result from lrclib.net API
struct LyricsSearchResult: Codable, Identifiable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case trackName
        case artistName
        case albumName
        case duration
        case instrumental
        case plainLyrics
        case syncedLyrics
    }
    
    /// Check if this result has synchronized (LRC) lyrics
    var hasSyncedLyrics: Bool {
        syncedLyrics != nil && !syncedLyrics!.isEmpty
    }
    
    /// Get LRC content (prefers synced, falls back to plain)
    var lrcContent: String? {
        if let synced = syncedLyrics, !synced.isEmpty {
            return synced
        }
        
        // Convert plain lyrics to simple LRC format (no timestamps)
        if let plain = plainLyrics, !plain.isEmpty {
            return plain.split(separator: "\n").map { String($0) }.joined(separator: "\n")
        }
        
        return nil
    }
}

// MARK: - Errors

enum LyricsServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case rateLimitExceeded
    case serverError(statusCode: Int)
    case noLyricsFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL"
        case .invalidResponse:
            return "Invalid response from lyrics server"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later"
        case .serverError(let code):
            return "Server error (status code: \(code))"
        case .noLyricsFound:
            return "No lyrics found for this track"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .rateLimitExceeded:
            return "Wait a few minutes before trying again"
        case .noLyricsFound:
            return "Try importing an LRC file manually"
        default:
            return "Check your internet connection and try again"
        }
    }
}

