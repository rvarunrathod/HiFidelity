# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

HiFidelity — macOS-only audiophile music player (SwiftUI + AppKit, macOS 14+, Swift 5, universal binary). No test target exists.

## Build & Run

- **Open in Xcode**: `open HiFidelity.xcodeproj` (Xcode 15+).
- **Local dev build (no signing)**: `./Scripts/build.sh --bypass-notary` from repo root or `Scripts/`. Auto-detects project root, reads `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from `project.pbxproj`, outputs DMG + `.sha256` under `build/`. Universal by default; flags: `--intel-only`, `--arm-only`, `--separate`, `--universal`, `--version <x.y.z>`, `--verbose`.
- **Signed + notarized release**: requires env `HiFidelity_TEAM_ID` and `HiFidelity_DEVELOPER_ID`, plus notarytool keychain profile named `HiFidelity` (`xcrun notarytool store-credentials HiFidelity ...`).
- **Generate test audio in all BASS formats**: `./Scripts/audio-gen.sh <input.flac>` (requires `ffmpeg`).
- **Bumping version**: edit `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `HiFidelity.xcodeproj/project.pbxproj` — `build.sh` reads these as the source of truth.

## Architecture

Single macOS app target `HiFidelity` (bundle id from project; debug builds use `.debug` suffix → separate DB file). MVVM-ish with shared singletons rather than DI; SwiftUI views observe `ObservableObject` controllers.

### Entry & lifecycle

- `HiFidelity/HiFidelityApp.swift` — `@main` SwiftUI `App`. Defines two scenes: `main-player` (`ModernPlayerLayout`) and `audio-effects` (`EqualizerView`). Installs menu commands (Playback, App, View) and routes them to `PlaybackController.shared`. Bridges to AppKit via `@NSApplicationDelegateAdaptor`.
- `Core/AppDelegate.swift` — owns `SPUStandardUpdaterController` (Sparkle), runs `AppCoordinator.initializeApp()` on launch and `cleanup()` on terminate, restores miniplayer state. `applicationShouldTerminateAfterLastWindowClosed` returns `false` (app stays alive when window closes).
- `Core/AppCoordinator.swift` — orchestrates security-scoped bookmark restoration, queue persistence, folder watcher startup/shutdown. Held by the `App` struct; also exposes `AppCoordinator.shared`.

### Layers

- `HiFidelity/Core/` — services and engines (singletons):
  - `Playback/PlaybackController.swift` + 10 `PlaybackController+*.swift` extensions (Controls, Queue, Shuffle, Gapless, Volume, Timer, Autoplay, Favorites, NowPlaying, RemoteCommands). Single source of truth for playback state; published `currentTrack`/`isPlaying`/`queue`/etc. drive the UI. Owns `BASSAudioEngine` and `RecommendationEngine.shared`.
  - `Audio/BASSAudioEngine.swift` — wraps the un4seen BASS C library (headers in `Core/Audio/bass-include/`, dylibs linked from project). Handles bit-perfect output, hog mode, sample-rate sync, gapless preload, exclusive device access. `AudioEffectsManager`, `DACManager`, `R128LoudnessScanner`, `AudioSettings`, `ReplayGainSettings` live alongside it.
  - `DatabaseManager/` — GRDB on SQLite (WAL, `synchronous=NORMAL`, 5s busy timeout). DB path: `~/Library/Application Support/<bundleID>/<bundleName>[-debug].db`. `Schema/DatabaseMigrator.swift` drives migrations on startup. Domain operations split across `ModelOperations/DB*.swift` files (DBTrack, DBPlaylist, DBQueue, DBSearch with FTS5, DBLyrics, DBSongFeatures, DBFolder, DBNormalizedEntities, DBEntityTracks). Helpers in `Utils/` (ArtworkCache, DatabaseCache, PathRecoveryManager, QueuePersistenceManager, RecommendationEngine, SecurityScopedBookmarkManager).
  - `MetadataExtraction/TagLib/` — Objective-C++ bridge (`.mm` + header, exposed via `Utils/HiFidelity-Bridging-Header.h`) calling the TagLib dylib in `HiFidelity/deps/lib/libtag.2.dylib` (headers in `deps/include/taglib/`).
  - `Remote/` — opt-in HTTP remote-control server (FlyingFox SPM dep). `RemoteControlServer` is a `@MainActor` singleton; route handlers run on FlyingFox's executor and explicitly hop via `await MainActor.run { ... }` for any `PlaybackController.shared` access. `Track.url` is never serialized (security-scoped). The bundled web client lives under `HiFidelity/Resources/RemoteControl/web/` (see Resources note below).
  - Top-level Core services: `MetadataManagement.swift` (~37 KB — central import/scan logic), `FolderWatcherService.swift` (FSEvents on user library folders), `LyricsService.swift` (lrclib download + parsing).
- `HiFidelity/Models/` — domain types (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `PlaylistTrack`, `Folder`, `QueueEntry`, `LyricLine`, `TrackLyrics`, `SongFeatures`). These are GRDB records and SwiftUI-facing models in one.
- `HiFidelity/Views/` — SwiftUI tree:
  - Root layouts: `ModernPlayerLayout.swift`, `ResponsiveMainLayout.swift`.
  - `Library/` (HomeView + Tracks/Albums/Artists/Genres tabs + EntityDetailView), `Playback/` (BottomPlaybackBar + controls), `MiniPlayer/` (separate `MiniPlayerWindowController` AppKit window with lyrics/queue panels), `Settings/` (Library/Audio/Appearance/Advanced/About + Equalizer + RemoteControl), `Playlists/`, `Search/`, `Navigation/`, `RightSidebar/`, `Shared/`, `Theme/` (`AppTheme` singleton + `AppFonts`).
- `HiFidelity/Utils/` — `LogLevel.swift` (the `Logger` used everywhere — install crash handler at startup, `setMinimumLogLevel` differs by build config), `M3UPlaylistHandler`, `StringNormalization`, `SystemInfo`, bridging header.
- `HiFidelity/AppData/` — `Constants.swift`, `AppInfo.swift` (reads `Bundle.main.infoDictionary` with fallback to `About.*`).
- `HiFidelity/Resources/` — bundled non-image assets. Currently houses `RemoteControl/web/` (the in-app remote-control web client: `index.html`, `app.js`, `style.css`). The directory is wired in via `PBXFileSystemSynchronizedRootGroup` in `project.pbxproj`, so adding files just works on disk — Xcode picks them up automatically. Reach files at runtime through `Bundle.main.url(forResource:withExtension:subdirectory:)`. Image assets continue to live in `HiFidelity/Assets.xcassets/`; vendored C/C++ libraries continue in `HiFidelity/deps/`.

### Key conventions in this codebase

- **Singletons everywhere**: `PlaybackController.shared`, `DatabaseManager.shared`, `AppTheme.shared`, `AppCoordinator.shared`, `FolderWatcherService.shared`, `QueuePersistenceManager.shared`, `RecommendationEngine.shared`, `RemoteControlServer.shared`. New code follows the same pattern; do not introduce DI frameworks.
- **`PlaybackController` is split by extension files**, not protocols. New playback feature → add `PlaybackController+<Feature>.swift` next to the others.
- **Database changes go through migrations** in `Core/DatabaseManager/Schema/DatabaseMigrator.swift`. Never alter schema directly. Domain queries belong in a new `DB<Entity>.swift` extension under `ModelOperations/`.
- **Logging**: use `Logger.info/debug/error/critical(...)` from `Utils/LogLevel.swift`, never `print`. Crash handler is installed in `HiFidelityApp.init()`.
- **Security-scoped resources**: any access to user-chosen folders must go through `SecurityScopedBookmarkManager` (sandboxed app — direct paths will fail at runtime). Bookmarks are restored on launch by `AppCoordinator.initializeApp`.
- **Two entitlements files** (`HiFidelity.entitlements` debug, `HiFidelityRelease.entitlements` release) — keep them in sync when adding capabilities.
- **Dependencies** are SPM (`GRDB.swift`, `Sparkle`, `FlyingFox`) plus vendored C/C++ libraries (BASS family in project, TagLib dylib in `HiFidelity/deps/`). Bridging header pulls in TagLib only.

## Release distribution

Sparkle auto-update is wired in `AppDelegate`. Released DMGs ship from GitHub Releases and a Homebrew tap (`brew install --cask rvarunrathod/tap/hifidelity`). The README installation instructions assume a Developer-ID-signed + notarized DMG — local `--bypass-notary` builds will trigger Gatekeeper warnings (`xattr -d com.apple.quarantine ...`).
