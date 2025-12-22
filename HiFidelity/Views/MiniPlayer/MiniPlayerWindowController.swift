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
        let initialHeight: CGFloat = 140 + 16  // content height + padding
        
        window.setContentSize(NSSize(width: initialWidth, height: initialHeight))
        
        // Prevent resizing - fixed size window
        window.minSize = NSSize(width: initialWidth, height: initialHeight)
        window.maxSize = NSSize(width: initialWidth, height: initialHeight)
        
        // Position window
        if let savedOrigin = Self.loadWindowPosition() {
            // Restore saved position
            window.setFrameOrigin(savedOrigin)
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
    }
    
    @objc internal func windowWillClose(_ notification: Notification) {
        // Save window position before closing
        if let window = window {
            Self.saveWindowPosition(window.frame.origin)
        }
        // Save closed state
        UserDefaults.standard.set(false, forKey: "miniPlayerWasOpen")
        MiniPlayerWindowController.shared = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidMove(_ notification: Notification) {
        // Save window position when it moves
        if let window = window {
            Self.saveWindowPosition(window.frame.origin)
        }
    }
    
    // MARK: - Position Persistence
    
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

