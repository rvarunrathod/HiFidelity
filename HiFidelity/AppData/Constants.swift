//
//  Constants.swift
//  HiFidelity
//
//  Created by Varun Rathod on 21/10/25.
//

import Foundation


// MARK: - Audio File Formats

struct AudioFormat {
    // Supported formats based on BASS audio library and extensions
    // See: https://github.com/Treata11/CBass
    static let supportedMusicFormat: [String] = [
        // Core BASS formats
        "mp3", "mp2",                  // MP3/MP2
        "ogg",                         // Ogg Vorbis
        "wav", "aiff", "aif",          // PCM formats
        
        // BASS_AAC - AAC/MP4 extension (macOS standard formats)
        "m4a", "m4b", "m4p",           // MPEG-4 Audio
        "mp4", "m4v",                  // MPEG-4 containers with audio
        "aac",                         // Advanced Audio Coding
        "caf",                         // Core Audio Format (macOS)
        
        // BASSFLAC - FLAC extension
        "flac", "oga",                        // FLAC (including Ogg FLAC)
        
        // BASSOPUS - Opus extension
        "opus",                        // Opus
        
        // BASSWV - WavPack extension
        "wv",                          // WavPack (including WavPack DSD)
        
        // BASSAPE - Monkey's Audio extension
        "ape",                         // Monkey's Audio
        
        // BASSWEBM - WebM/Matroska extension
        "webm",                        // WebM
        
        // BASS_MPC - Musepack extension
        "mpc",                         // Musepack
        
        // BASS_TTA - TTA extension
        "tta",                         // TTA (True Audio)
        
        // BASS_SPX - Speex extension
        "spx",                         // Speex 
        
        // BASSDSD - DSD extension
        "dff", "dsf"                   // DSD (Direct Stream Digital)
    ]
    
    static var supportedFormatsDisplay: String {
        supportedMusicFormat
            .map { $0.uppercased() }
            .joined(separator: ", ")
    }
    
    static func isSupported(_ fileExtension: String) -> Bool {
        supportedMusicFormat.contains(fileExtension.lowercased())
    }
    
    static func isNotSupported(_ fileExtension: String) -> Bool {
        !supportedMusicFormat.contains(fileExtension.lowercased())
    }
    
}

// MARK: - About

enum About {
    static let bundleIdentifier = "vr.HiFidelity"
    static let appTitle = "HiFidelity"
    static let bundleName = "hifidelity"
    static let appWebsite = "https://github.com/rvarunrathod/HiFidelity"
    static let appWiki = "https://github.com/rvarunrathod/HiFidelity/wiki"
    static let sponsor = "https://github.com/sponsors/rvarunrathod"
    static let appVersion = "1.0.8"
    static let appBuild = "108"
}


// MARK: - Global Event Notifications

extension Notification.Name {
    // Library data changes
    static let libraryDataDidChange = Notification.Name("LibraryDataDidChange")
    static let refreshLibraryData = Notification.Name("RefreshLibraryData") // Manual refresh triggered by user
    static let foldersDataDidChange = Notification.Name("FoldersDataDidChange")
    static let playlistsDidChange = Notification.Name("PlaylistsDidChange")
    static let playlistCreated = Notification.Name("PlaylistCreated") // Includes playlist object for auto-add functionality
    
    // Navigation
    static let goToLibraryFilter = Notification.Name("GoToLibraryFilter")
    static let goToHome = Notification.Name("GoToHome")
    static let navigateToEntity = Notification.Name("NavigateToEntity")

    
    // Playback
    static let playEntityTracks = Notification.Name("playEntityTracks")
    static let playPlaylistTracks = Notification.Name("playPlaylistTracks")
    
    // UI
    static let trackTableSortChanged = Notification.Name("trackTableSortChanged")
    static let trackTableRowSizeChanged = Notification.Name("trackTableRowSizeChanged")
    static let focusSearchField = Notification.Name("FocusSearchField")
    static let dismissAllFocus = Notification.Name("DismissAllFocus")
    
    // Settings
    static let openSettingsAbout = Notification.Name("OpenSettingsAbout")
    static let openSettings = Notification.Name("OpenSettings")
}
