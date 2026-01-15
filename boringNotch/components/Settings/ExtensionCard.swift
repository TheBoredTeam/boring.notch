//
//  ExtensionCard.swift
//  boringNotch
//
//  Created by sleepy on 2026. 01. 14..
//

import SwiftUI

struct ExtensionCard: View {
    let extensionDescriptor: ExtensionDescriptor
    let isInstalled: Bool
    
    @ObservedObject var manager = ExtensionManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: extensionDescriptor.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .padding(8)
                    .background(Color(NSColor.controlColor)) // Slightly darker/lighter
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(extensionDescriptor.name)
                        .font(.headline)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Version: \(extensionDescriptor.version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if extensionDescriptor.isBuiltIn {
                    Text("Built-in")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // Description
            Text(extensionDescriptor.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Developer Info & Actions
            HStack(spacing: 16) {
                // Left side: Developer Info
                HStack(spacing: 4) {
                    if extensionDescriptor.isBuiltIn {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                    }
                    Text(extensionDescriptor.developer)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Right side: Actions
                if isInstalled {
                    HStack(spacing: 12) {
                        // Enable/Disable Toggle
                        Toggle("Enabled", isOn: extensionDescriptor.binding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(Color.effectiveAccent)
                            .help(extensionDescriptor.binding.wrappedValue ? "Disable extension" : "Enable extension")
                        
                        // Configure Button
                        if let settingsView = extensionDescriptor.settingsView {
                            NavigationLink(destination: settingsView()) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Configure settings")
                        }
                        
                        // Uninstall Button
                        Button {
                            withAnimation {
                                manager.uninstall(extensionID: extensionDescriptor.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.red.opacity(0.8))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove extension")
                    }
                } else {
                    // Install Button
                    Button("Install") {
                        withAnimation {
                            manager.download(extensionID: extensionDescriptor.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
