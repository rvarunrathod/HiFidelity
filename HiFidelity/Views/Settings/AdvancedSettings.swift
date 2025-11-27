//
//  AdvancedSettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

struct AdvancedSettings: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @AppStorage("artworkCacheSize") private var cacheSize: Double = 500
    @State private var showResetConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Performance
            performanceSection
            
            Divider()
            
            // Database
            databaseSection
            
            Divider()
            
            // Danger Zone
            dangerZone
            
            Spacer()
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Performance")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Artwork Cache Size")
                    Spacer()
                    Text("\(Int(cacheSize)) MB")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                
                Slider(value: $cacheSize, in: 100...1000, step: 100)
                    .onChange(of: cacheSize) { _, newValue in
                        applyCacheSize(Int(newValue))
                    }
                
                Text("Memory limit for caching album artwork. Larger cache = smoother scrolling.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Database")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Size")
                        .font(.subheadline)
                    if let size = databaseManager.getDatabaseSize() {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        try? await databaseManager.vacuumDatabase()
                    }
                } label: {
                    Text("Optimize")
                        .font(.subheadline)
                }
            }
        }
    }
    
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Danger Zone")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.red)
            
            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Reset Database")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .alert("Reset Database?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task {
                        try? databaseManager.resetDatabase()
                    }
                }
            } message: {
                Text("This will delete all your music library data. This action cannot be undone.")
            }
            
            Text("⚠️ This will permanently delete all your library data including folders, tracks, and playlists.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func applyCacheSize(_ sizeMB: Int) {
        ArtworkCache.shared.updateCacheSize(sizeMB: sizeMB)
    }

} 

#Preview {
    AdvancedSettings()
        .environmentObject(DatabaseManager.shared)
        .frame(width: 600, height: 600)
}
