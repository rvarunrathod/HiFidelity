//
//  MiniPlayerWindowController.swift
//  HiFidelity
//
//  Window controller for mini player
//

import AppKit
import SwiftUI

/// Custom window class that doesn't activate the app when clicked
class MiniPlayerWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true  // Allow keyboard input
    }
    
    override func makeKey() {
        // Override to prevent activating the app when clicking buttons
        super.makeKey()
        // Don't activate the application
    }
}

/// Window controller for managing the mini player window
class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {
    static var shared: MiniPlayerWindowController?
    
    convenience init() {
        // Create the SwiftUI view
        let miniPlayerView = MiniPlayerView()
        
        // Wrap in a hosting controller
        let hostingController = NSHostingController(rootView: miniPlayerView)
        
        // Create the custom window
        let window = MiniPlayerWindow(contentViewController: hostingController)
        
        // Set window title (hidden but used for identification)
        window.title = "Mini Player"
        
        // Configure window appearance - only close button, no title bar
        window.styleMask = [.closable, .fullSizeContentView, .borderless]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        
        // Configure window to have rounded corners
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }
        
        // Invalidate shadow to update with rounded corners
        window.invalidateShadow()
        
        // Configure toolbar to be transparent
        let toolbar = NSToolbar()
        toolbar.displayMode = .iconOnly
        toolbar.isVisible = false
        window.toolbar = toolbar
        
        // Set window level based on user preference
        let isFloatable = UserDefaults.standard.bool(forKey: "miniPlayerFloatable")
        window.level = (UserDefaults.standard.object(forKey: "miniPlayerFloatable") == nil || isFloatable) ? .floating : .normal
        
        // Set initial size (140 content height + 16 padding = 156)
        let showArtwork = UserDefaults.standard.object(forKey: "miniPlayerShowArtwork") as? Bool ?? true
        let initialWidth: CGFloat = (showArtwork ? 440 : 360) + 16  // +16 for padding
        let initialHeight = Self.collapsedHeight
        
        window.setContentSize(NSSize(width: initialWidth, height: initialHeight))
        
        // Prevent resizing - fixed size window
        window.minSize = NSSize(width: initialWidth, height: initialHeight)
        window.maxSize = NSSize(width: initialWidth, height: initialHeight)
        
        // Position window
        // Restore saved position, pulled fully onto its screen; ignore it if no screen shows it
        // anymore (e.g. external display removed)
        if let savedOrigin = Self.loadWindowPosition(),
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: savedOrigin, size: window.frame.size)) }) {
            window.setFrame(Self.clamp(NSRect(origin: savedOrigin, size: window.frame.size), to: screen.visibleFrame), display: false)
        } else if let screen = NSScreen.main {
            // Default position in bottom right corner with padding
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            
            let x = screenRect.maxX - windowRect.width - 20
            let y = screenRect.minY + 20
            
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Make window collection behavior appropriate for a utility window
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        // Prevent mini player from activating the app and bringing main window forward
        window.hidesOnDeactivate = false
        
        // Initialize with the window
        self.init(window: window)
        
        // Store reference
        MiniPlayerWindowController.shared = self
        
        // Set window delegate to track position changes
        window.delegate = self
        
        // Observe window close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )

        // Keep the window on screen when displays are added, removed or rearranged
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(Self.clamp(window.frame, to: screen.visibleFrame), display: true)
    }

    @objc internal func windowWillClose(_ notification: Notification) {
        // Save window position before closing
        if let window = window {
            Self.saveWindowPosition(collapsedOrigin(of: window))
        }
        // Save closed state
        UserDefaults.standard.set(false, forKey: "miniPlayerWasOpen")
        MiniPlayerWindowController.shared = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidMove(_ notification: Notification) {
        // Save window position when it moves
        if let window = window {
            Self.saveWindowPosition(collapsedOrigin(of: window))
        }
    }

    // MARK: - Position Persistence

    static let collapsedHeight: CGFloat = 140 + 16  // content height + padding

    /// Whether the open Queue/Lyrics panel grew upward (bottom edge fixed) instead of downward
    var expandedUpward = false

    /// Move `frame` so it lies fully inside `visible`
    static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var frame = frame
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        return frame
    }

    /// Origin the window has when the Queue/Lyrics panel is closed, so reopening doesn't land 300pt off
    private func collapsedOrigin(of window: NSWindow) -> NSPoint {
        let extra = window.frame.height - Self.collapsedHeight
        guard extra > 0, !expandedUpward else { return window.frame.origin }
        return NSPoint(x: window.frame.minX, y: window.frame.minY + extra)
    }

    private static func saveWindowPosition(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: "miniPlayerWindowX")
        UserDefaults.standard.set(origin.y, forKey: "miniPlayerWindowY")
    }
    
    private static func loadWindowPosition() -> NSPoint? {
        guard UserDefaults.standard.object(forKey: "miniPlayerWindowX") != nil else {
            return nil
        }
        
        let x = CGFloat(UserDefaults.standard.double(forKey: "miniPlayerWindowX"))
        let y = CGFloat(UserDefaults.standard.double(forKey: "miniPlayerWindowY"))
        
        return NSPoint(x: x, y: y)
    }
    
    /// Toggle mini player visibility
    static func toggle() {
        if let controller = shared {
            // Close existing mini player
            controller.close()
            shared = nil
            // Save closed state
            UserDefaults.standard.set(false, forKey: "miniPlayerWasOpen")
        } else {
            // Open new mini player
            let controller = MiniPlayerWindowController()
            controller.showWindow(nil)
            // Use orderFront instead of makeKeyAndOrderFront to prevent activating the app
            controller.window?.orderFront(nil)
            // Save open state
            UserDefaults.standard.set(true, forKey: "miniPlayerWasOpen")
        }
    }
    
    /// Show the mini player
    static func show() {
        if shared == nil {
            let controller = MiniPlayerWindowController()
            controller.showWindow(nil)
            // Use orderFront instead of makeKeyAndOrderFront to prevent activating the app
            controller.window?.orderFront(nil)
            // Save open state
            UserDefaults.standard.set(true, forKey: "miniPlayerWasOpen")
        } else {
            shared?.showWindow(nil)
            shared?.window?.orderFront(nil)
        }
    }
    
    /// Main window hidden when entering the mini player.
    /// The "MainPlayerWindow" identifier alone is unreliable: after SwiftUI recreates the main window
    /// it ends up on a hidden helper window, and ordering that front blocks Dock reopen.
    private static weak var hiddenMainWindow: NSWindow?

    /// Hide the main window and show the mini player
    static func showHidingMainWindow() {
        if let mainWindow = NSApp.mainWindow {
            hiddenMainWindow = mainWindow
            mainWindow.orderOut(nil)
        }
        show()
    }

    /// Close the mini player and bring the main window back
    static func closeAndShowMainWindow() {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let mainWindowId = NSUserInterfaceItemIdentifier("MainPlayerWindow")
            let mainWindow = hiddenMainWindow
                ?? NSApp.windows.first(where: { $0.identifier == mainWindowId && $0.canBecomeMain })
            hiddenMainWindow = nil
            if let mainWindow {
                mainWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Hide the mini player
    static func hide() {
        shared?.close()
        shared = nil
        // Save closed state
        UserDefaults.standard.set(false, forKey: "miniPlayerWasOpen")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let toggleMiniPlayer = Notification.Name("toggleMiniPlayer")
}

