//
//  ExtensionsHubView.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI
import Defaults

// MARK: - Navigation Destinations
enum ExtensionDestination: Hashable {
    case marketplace
    case extensionDetail(ExtensionDescriptor)
}

// Make ExtensionDescriptor Hashable for navigation
extension ExtensionDescriptor: Hashable {
    static func == (lhs: ExtensionDescriptor, rhs: ExtensionDescriptor) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Main Hub View (Root)
struct ExtensionsHubView: View {
    @ObservedObject var manager = ExtensionManager.shared
    @State private var searchText = ""
    @State private var navigationPath = NavigationPath()
    
    var filteredInstalled: [ExtensionDescriptor] {
        if searchText.isEmpty { return manager.installedExtensions }
        return manager.installedExtensions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Installed Extensions
                    if !filteredInstalled.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Installed Extensions")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredInstalled) { ext in
                                    ExtensionCard(extensionDescriptor: ext, isInstalled: true)
                                }
                            }
                        }
                    } else {
                        // Empty State
                        VStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No extensions installed")
                                .font(.headline)
                            Text("Visit the marketplace to add new features")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                    
                    // Footer with Marketplace Button
                    VStack(spacing: 8) {
                        Divider()
                            .padding(.vertical, 8)
                        
                        Button(action: {
                            navigationPath.append(ExtensionDestination.marketplace)
                        }) {
                            HStack {
                                Image(systemName: "cart.fill")
                                Text("Browse Marketplace")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Text("Discover new extensions created by the community")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 20)
                }
                .padding()
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search installed extensions")
            .navigationTitle("Extensions")
            .navigationDestination(for: ExtensionDestination.self) { destination in
                switch destination {
                case .marketplace:
                    MarketplaceView(navigationPath: $navigationPath)
                case .extensionDetail(let ext):
                    ExtensionDetailView(extensionDescriptor: ext, navigationPath: $navigationPath)
                }
            }
        }
    }
}

// MARK: - Marketplace View (Push Navigation)
struct MarketplaceView: View {
    @ObservedObject var manager = ExtensionManager.shared
    @Binding var navigationPath: NavigationPath
    @State private var searchText = ""
    @State private var selectedTab = "Popular"
    
    let columns = [
        GridItem(.flexible(), spacing: 20)
    ]
    
    var filteredExtensions: [ExtensionDescriptor] {
        if searchText.isEmpty { return manager.marketplaceExtensions }
        return manager.marketplaceExtensions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Header
            VStack(spacing: 20) {
                // Prominent Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                    TextField("Search extensions", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                // Filter Tabs
                HStack(spacing: 16) {
                    ForEach(["Popular", "New", "Featured"], id: \.self) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            Text(tab)
                                .font(.body)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .background(selectedTab == tab ? Color.effectiveAccent.opacity(0.1) : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            
            Divider()
            
            // Content Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredExtensions) { ext in
                        MarketplaceItemCard(extensionDescriptor: ext)
                            .onTapGesture {
                                navigationPath.append(ExtensionDestination.extensionDetail(ext))
                            }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Marketplace")
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Marketplace Item Card
struct MarketplaceItemCard: View {
    let extensionDescriptor: ExtensionDescriptor
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: extensionDescriptor.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.effectiveAccent.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(extensionDescriptor.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(extensionDescriptor.developer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text(extensionDescriptor.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Extension Detail View (Push Navigation)
struct ExtensionDetailView: View {
    let extensionDescriptor: ExtensionDescriptor
    @ObservedObject var manager = ExtensionManager.shared
    @Binding var navigationPath: NavigationPath
    
    var isInstalled: Bool {
        manager.installedExtensions.contains(where: { $0.id == extensionDescriptor.id })
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Section
                VStack(spacing: 24) {
                    Image(systemName: extensionDescriptor.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(Color.effectiveAccent.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    
                    VStack(spacing: 8) {
                        Text(extensionDescriptor.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(extensionDescriptor.developer)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Action Button
                    if isInstalled {
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Installed")
                            }
                            .frame(maxWidth: 400)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    } else {
                        Button(action: {
                            withAnimation {
                                manager.download(extensionID: extensionDescriptor.id)
                                // Pop back to marketplace after download
                                navigationPath.removeLast()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download")
                            }
                            .font(.headline)
                            .frame(maxWidth: 400)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 32)
                
                Divider()
                    .padding(.vertical, 24)
                
                // Content Sections
                VStack(alignment: .leading, spacing: 32) {
                    // Screenshots/Media Placeholder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Preview")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(0..<3) { index in
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .frame(width: 320, height: 200)
                                        .overlay(
                                            VStack {
                                                Image(systemName: "photo")
                                                    .font(.largeTitle)
                                                    .foregroundStyle(.tertiary)
                                                Text("Screenshot \(index + 1)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        )
                                }
                            }
                        }
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(extensionDescriptor.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                    }
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 8) {
                            ForEach(["Productivity", "Media", "Utilities"], id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.effectiveAccent.opacity(0.1))
                                    .foregroundStyle(Color.effectiveAccent)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Information")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 12) {
                            MetadataRow(label: "Version", value: extensionDescriptor.version)
                            MetadataRow(label: "Developer", value: extensionDescriptor.developer)
                            MetadataRow(label: "Created", value: "January 14, 2026")
                            MetadataRow(label: "Last Updated", value: "Just now")
                            MetadataRow(label: "Size", value: "2.4 MB")
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(extensionDescriptor.name)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Helper View
struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }
}
