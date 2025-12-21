//
//  HiFidelityApp.swift
//  HiFidelity
//
//  Created by Varun Rathod on 21/10/25.
//

import SwiftUI
import SwiftData
import AppKit

/// Main SwiftUI App entry point for HiFidelity
/// AppDelegate is defined in Core/AppDelegate.swift
@main
struct HiFidelityApp: App {
    // Connects to AppDelegate for macOS-specific lifecycle events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private let appCoordinator = AppCoordinator()
    @StateObject private var appTheme = AppTheme.shared

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ModernPlayerLayout()
                .environmentObject(DatabaseManager.shared)
                .environmentObject(appTheme)
                .environmentObject(appCoordinator)
                .themedAccentColor(appTheme)
                .onAppear {
                    configureWindow()
                }
        }
        .commands {
            // Playback Control Commands
            playbackCommands()
            
            // App Menu Commands
            appMenuCommands()
            
            // View Menu Commands
            viewMenuCommands()
            
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)

        
        equalizerWindowContentView()
        
    }
    
    init() {
        // Install crash handlers and configure logger
        Logger.installCrashHandler()
        
        #if DEBUG
        Logger.setMinimumLogLevel(.debug)
        #else
        Logger.setMinimumLogLevel(.info)
        #endif
        
        Logger.info("HiFidelity SwiftUI app initialized")
        
        // Print system information for debugging
        SystemInfo.printStartupInfo()
    }
    
    // MARK: - Window Configuration
    
    private func configureWindow() {
        // Configure window for custom title bar with native controls
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            
            // Set toolbar background for better contrast
            window.toolbar?.insertItem(withItemIdentifier: .init("separator"), at: 0)
            
            // Configure toolbar appearance
            if let toolbar = window.toolbar {
                toolbar.displayMode = .iconOnly
            }
        }
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            Logger.debug("Scene entered background")
            // Save queue when app goes to background
            Task {
                await QueuePersistenceManager.shared.saveNow()
            }
        case .inactive:
            Logger.debug("Scene became inactive")
        case .active:
            Logger.debug("Scene became active")
        @unknown default:
            break
        }
    }
    
    private func equalizerWindowContentView() -> some Scene {
        // Separate window for Equalizer (single instance only)
        Window("Equalizer", id: "audio-effects") {
            EqualizerView()
                .environmentObject(appTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    
    @CommandsBuilder
    private func appMenuCommands() -> some Commands {
        CommandGroup(replacing: .appSettings) {}
        
        CommandGroup(replacing: .appInfo) {
            Button("About HiFidelity") {
                NotificationCenter.default.post(name: .openSettingsAbout, object: nil)
            }
        }
        
        CommandGroup(after: .appInfo) {
            Divider()
            checkForUpdatesMenuItem()
        }
    }
    
    // MARK: - View Menu Commands
    
    @CommandsBuilder
    private func viewMenuCommands() -> some Commands {
        CommandGroup(after: .toolbar) {
            miniPlayerCommand()
            audioEffects()
//            visualEffects()
        }
    }
    
    private func checkForUpdatesMenuItem() -> some View {
        Button {
            if let updater = appDelegate.updaterController?.updater {
                updater.checkForUpdates()
            }
        } label: {
            Text("Check for Updates...")
        }
    }
    
    
    
//    private func visualEffects() -> some View {
//        Menu("Visualizer") {
//            Button("Toggle Visualizer") {
//                openWindow(id: "visualizer")
//            }
//            .keyboardShortcut("v", modifiers: .command)
//        }
//    }
    
    private func miniPlayerCommand() -> some View {
        Button {
            MiniPlayerWindowController.toggle()
        } label: {
            Text("Mini Player")
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
    
    private func audioEffects() -> some View {
        Button {
            openWindow(id: "audio-effects")
        } label: {
            Text("Equalizer")
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
    }
    
    // MARK: - Playback Commands
    
    @CommandsBuilder
    private func playbackCommands() -> some Commands {
        CommandMenu("Playback") {
            Button(action: {
                PlaybackController.shared.togglePlayPause()
            }) {
                Text(PlaybackController.shared.isPlaying ? "Pause" : "Play")
            }
            .keyboardShortcut(.space, modifiers: [])
            
            Divider()
            
            Button("Next Track") {
                PlaybackController.shared.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            
            Button("Previous Track") {
                PlaybackController.shared.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            
            Divider()
            
            Button("Seek Forward") {
                PlaybackController.shared.seekForward(10.0)
            }
            .keyboardShortcut(.rightArrow, modifiers: .shift)
            
            Button("Seek Backward") {
                PlaybackController.shared.seekBackward(10.0)
            }
            .keyboardShortcut(.leftArrow, modifiers: .shift)
            
            Divider()
            
            Button("Volume Up") {
                let newVolume = min(PlaybackController.shared.volume + 0.05, 1.0)
                PlaybackController.shared.volume = newVolume
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            
            Button("Volume Down") {
                let newVolume = max(PlaybackController.shared.volume - 0.05, 0.0)
                PlaybackController.shared.volume = newVolume
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            
            Divider()
            
            Button("Toggle Shuffle") {
                PlaybackController.shared.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: .command)
            
            Button("Toggle Repeat") {
                PlaybackController.shared.toggleRepeat()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }

}
