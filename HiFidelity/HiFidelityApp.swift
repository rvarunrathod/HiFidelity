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
            // View menu with audio effects
            audioEffectsCommands()
            
            appMenuCommands()
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
        Logger.setMinimumLogLevel(.info)
        #else
        Logger.setMinimumLogLevel(.warning)
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
        // Separate window for Equalizer (non-blocking)
        WindowGroup("Equalizer", id: "audio-effects") {
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
    
    private func checkForUpdatesMenuItem() -> some View {
        Button {
            if let updater = appDelegate.updaterController?.updater {
                updater.checkForUpdates()
            }
        } label: {
            Text("Check for Updates...")
        }
    }
    
    
    @CommandsBuilder
    private func audioEffectsCommands() -> some Commands {
        CommandGroup(after: .toolbar) {
            Menu("DSP") {
                Button {
                    openWindow(id: "audio-effects")
                } label: {
                    Text("Equalizer")
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }
            
            Divider()
        }
        
    }

}
