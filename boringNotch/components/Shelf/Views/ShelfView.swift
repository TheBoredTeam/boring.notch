//
//  ShelfView.swift
//  boringNotch
//
//  Created by Antigravity on 2026-05-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                    handleDrop(providers: providers)
                }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        ClipboardManager.shared.ingestDroppedProviders(providers)
        return true
    }
    
    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                ClipboardShelfView()
                    .environmentObject(vm)
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Clipboard Shelf View Components

import UniformTypeIdentifiers

struct ClipboardShelfView: View {
    @ObservedObject var manager = ClipboardManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var searchText: String = ""
    
    private var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            return manager.items
        } else {
            return manager.items.filter {
                $0.previewText.localizedCaseInsensitiveContains(searchText) ||
                $0.contentValue.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            headerBar
            
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems, id: \.id) { item in
                            ClipboardItemCard(item: item)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation(.smooth) {
                            searchText = ""
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            
            Spacer()
            
            Button(action: {
                withAnimation(.smooth) {
                    manager.clearAllNonPinned()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Clear All")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.red.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.red.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .font(.system(size: 24))
            
            Text(searchText.isEmpty ? "Clipboard is empty" : "No results found")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardItemCard: View {
    let item: ClipboardItem
    @ObservedObject var manager = ClipboardManager.shared
    @State private var isHovered = false
    @State private var isJustCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 6) {
                    Text(item.contentType.displayLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(item.contentType.labelColor.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(item.contentType.labelColor.opacity(0.12))
                        .cornerRadius(3)
                    
                    Text(timeAgo(from: item.timestamp))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer(minLength: 12)
            
            if isHovered || item.isPinned {
                HStack(spacing: 4) {
                    Button(action: {
                        withAnimation(.smooth) {
                            manager.togglePin(item)
                        }
                    }) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                            .foregroundColor(item.isPinned ? .orange : .gray)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        withAnimation(.smooth) {
                            manager.deleteItem(item)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isJustCopied ? Color.green.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isJustCopied ? Color.green.opacity(0.5) : (isHovered ? Color.white.opacity(0.12) : Color.clear), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isJustCopied = true
            }
            manager.restoreToClipboard(item)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isJustCopied = false
                }
            }
        }
        .onDrag {
            return makeDragItemProvider()
        }
    }
    
    private func makeDragItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        
        switch item.contentType {
        case .plainText, .codeSnippet:
            provider.registerObject(item.contentValue as NSString, visibility: .all)
            
        case .richText:
            provider.registerObject(item.contentValue as NSString, visibility: .all)
            if let rtf = item.rtfData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                    completion(rtf, nil)
                    return nil
                }
            }
            if let html = item.htmlData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.html.identifier, visibility: .all) { completion in
                    completion(html, nil)
                    return nil
                }
            }
            
        case .url:
            if let url = URL(string: item.contentValue) {
                provider.registerObject(url as NSURL, visibility: .all)
            } else {
                provider.registerObject(item.contentValue as NSString, visibility: .all)
            }
            
        case .file:
            if let paths = try? JSONDecoder().decode([String].self, from: item.contentValue.data(using: .utf8) ?? Data()),
               let firstPath = paths.first {
                let url = URL(fileURLWithPath: firstPath)
                provider.registerObject(url as NSURL, visibility: .all)
            }
            
        case .image:
            if let imageURL = manager.imageURL(for: item) {
                provider.registerObject(imageURL as NSURL, visibility: .all)
            }
        }
        
        return provider
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch item.contentType {
        case .image:
            if let imageURL = manager.imageURL(for: item) {
                LocalThumbnailView(fileURL: imageURL)
            } else {
                defaultIconPlaceholder
            }
        default:
            defaultIconPlaceholder
        }
    }
    
    @ViewBuilder
    private var defaultIconPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 12))
                .foregroundColor(item.contentType.labelColor)
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct LocalThumbnailView: View {
    let fileURL: URL
    @State private var image: NSImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
        }
        .task {
            if let loaded = NSImage(contentsOf: fileURL) {
                let size = CGSize(width: 56, height: 56)
                let resized = loaded.resized(to: size)
                self.image = resized
            }
        }
    }
}

extension NSImage {
    func resized(to newSize: CGSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

extension ClipboardItemType {
    var displayLabel: String {
        switch self {
        case .plainText: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .url: return "Link"
        case .file: return "File"
        case .codeSnippet: return "Code"
        }
    }
    
    var iconName: String {
        switch self {
        case .plainText: return "doc.text.fill"
        case .richText: return "doc.richtext.fill"
        case .image: return "photo.fill"
        case .url: return "link"
        case .file: return "doc.fill"
        case .codeSnippet: return "curlybraces"
        }
    }
    
    var labelColor: Color {
        switch self {
        case .plainText: return .blue
        case .richText: return .purple
        case .image: return .green
        case .url: return .teal
        case .file: return .orange
        case .codeSnippet: return .red
        }
    }
}
