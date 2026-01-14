//
//  ExtensionsHubView.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI

struct ExtensionsHubView: View {
    @ObservedObject var manager = ExtensionManager.shared
    @State private var searchText = ""
    
    var filteredInstalled: [ExtensionDescriptor] {
        if searchText.isEmpty { return manager.installedExtensions }
        return manager.installedExtensions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredAvailable: [ExtensionDescriptor] {
        if searchText.isEmpty { return manager.availableExtensions }
        return manager.availableExtensions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // Adaptive columns for responsive grid
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // Installed Extensions
                if !filteredInstalled.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Installed")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredInstalled) { ext in
                                ExtensionCard(extensionDescriptor: ext, isInstalled: true)
                            }
                        }
                    }
                }
                
                // Available Extensions
                if !filteredAvailable.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredAvailable) { ext in
                                ExtensionCard(extensionDescriptor: ext, isInstalled: false)
                            }
                        }
                    }
                }
                
                // Empty State
                if filteredInstalled.isEmpty && filteredAvailable.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No extensions found")
                            .font(.headline)
                        Text("Try a different search term")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
                
                // Footer
                HStack {
                    Spacer()
                    Button("Install from File...") {
                        // Future implementation
                    }
                    .disabled(true)
                    .controlSize(.small)
                    Spacer()
                }
                .padding(.top, 20)
            }
            .padding()
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search extensions")
        .navigationTitle("Extensions")
    }
}
