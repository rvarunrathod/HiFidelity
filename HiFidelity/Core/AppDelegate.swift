//
//  AppDelegate.swift
//  HiFidelity
//
//  App lifecycle delegate for macOS-specific functionality
//

import AppKit
import Foundation
import Sparkle

/// AppDelegate handles application lifecycle events and macOS-specific functionality
class AppDelegate: NSObject, NSApplicationDelegate {
    internal var updaterController: SPUStandardUpdaterController?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.info("HiFidelity is starting up...")
        
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Remove unwanted menus
        DispatchQueue.main.async {
            self.removeUnwantedMenus()
        }
        
        // Initialize app coordinator
        Task {
            await AppCoordinator.shared?.initializeApp()
        }
        
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Restore miniplayer if it was open when the app closed
        restoreMiniPlayerState()
        
        Logger.info("Application did finish launching")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.info("Application will terminate - performing cleanup")
        
        // Perform critical cleanup synchronously and quickly
        // Don't use semaphores or timeouts - let Swift handle async cleanup
        
        // 1. Stop audio immediately (most critical for clean shutdown)
        PlaybackController.shared.stop()
        
        // 2. Stop folder monitoring
        FolderWatcherService.shared.stopWatching()
        
        // 3. Save queue state quickly (non-blocking)
        Task.detached(priority: .high) {
            await QueuePersistenceManager.shared.stop()
            await AppCoordinator.shared?.cleanup()
        }
        
        // 4. Cleanup audio engine (synchronous, fast)
        // Audio engine is accessed through PlaybackController
        PlaybackController.shared.audioEngine.cleanup()
        
        Logger.info("Application cleanup complete")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running even when last window is closed (standard macOS behavior)
        return false
    }
    
    // MARK: - Application State Changes
    
    func applicationDidBecomeActive(_ notification: Notification) {
        Logger.debug("Application became active")
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        Logger.debug("Application resigned active")
        
        // Save queue when app loses focus
        Task {
            await QueuePersistenceManager.shared.saveNow()
        }
    }
    
    func applicationWillHide(_ notification: Notification) {
        Logger.debug("Application will hide")
        
        // Save queue when app is hidden (Cmd+H)
        Task {
            await QueuePersistenceManager.shared.saveNow()
        }
    }
    
    func applicationDidUnhide(_ notification: Notification) {
        Logger.debug("Application did unhide")
    }
    
    // MARK: - Window Management
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Enable secure state restoration
        return true
    }
    
    private func removeUnwantedMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        
        // Remove File menu
        if let fileMenu = mainMenu.item(withTitle: "File") {
            mainMenu.removeItem(fileMenu)
        }
        
        // Remove Format menu
        if let formatMenu = mainMenu.item(withTitle: "Format") {
            mainMenu.removeItem(formatMenu)
        }
        
        // Modify View menu
        if let viewMenu = mainMenu.item(withTitle: "View"),
           let viewSubmenu = viewMenu.submenu {
            // Remove tab-related items
            if let showTabBar = viewSubmenu.item(withTitle: "Show Tab Bar") {
                viewSubmenu.removeItem(showTabBar)
            }
            if let showAllTabs = viewSubmenu.item(withTitle: "Show All Tabs") {
                viewSubmenu.removeItem(showAllTabs)
            }
        }
    }
    
    // MARK: - Miniplayer State Restoration
    
    private func restoreMiniPlayerState() {
        // Check if miniplayer was open when app was last closed
        let wasOpen = UserDefaults.standard.bool(forKey: "miniPlayerWasOpen")
        
        if wasOpen {
            // Add a small delay to ensure main window is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MiniPlayerWindowController.show()
                Logger.debug("Restored miniplayer state - reopening miniplayer")
            }
        }
    }
}

