//
//  DockSettings.swift
//  boringNotch
//
//  Created by nahel belmadani on 19/03/2026.
//

import SwiftUI
import Defaults
import Kingfisher

struct DockSettings : View {
    @Default(.showDock) var showDock
    @Default(.showDockLabels) var showDockLabels
    @Default(.maxItemsPerColumn) var maxItemsPerColumn

    @Default(.dockItems) var dockItems
    
    @State private var selectedListDockItem: DockItem? = nil
    
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var imageUrl: String = ""
    
    @State private var currentEditingDockItem: DockItem? = nil
    
    @State private var fetchTask: Task<Void, Never>? = nil
    
    func fetchOGImage(from url: URL) async -> URL? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            //try favicon first
            let faviconPattern = #"<link rel="[^"]*icon[^"]*" href="([^"]+)""#
            let faviconRegex = try NSRegularExpression(pattern: faviconPattern)
            let faviconRange = NSRange(html.startIndex..., in: html)
            if let faviconMatch = faviconRegex.firstMatch(in: html, range: faviconRange),   let faviconURLRange = Range(faviconMatch.range(at: 1), in: html) {
                let faviconUrlString = String(html[faviconURLRange])
                if let faviconURL = URL(string: faviconUrlString, relativeTo: url) {
                    return faviconURL
                }
            }
            
            
            // Regex pour og:image
            let pattern = #"<meta property="og:image" content="([^"]+)""#
            let regex = try NSRegularExpression(pattern: pattern)
            
            let range = NSRange(html.startIndex..., in: html)
            
            if let match = regex.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                
                let imageUrlString = String(html[urlRange])
                return URL(string: imageUrlString)
            }
            
        } catch {
            print("Error fetching OG image:", error)
        }
        
        return nil
    }
    
    
    struct DockItemRow: View {
        let dockItem: DockItem
        let isSelected: Bool

        var body: some View {
            HStack {
                if ( dockItem.imageURL != nil) {
                    KFImage(dockItem.imageURL)
                        .placeholder {
                            ProgressView()
                        }
                        .onFailure { error in
                            print("Image failed:", error)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .opacity(0.5)
                }
                Text(dockItem.name)
                Spacer()
                Text(dockItem.url.host ?? "")
            }
            .padding(.vertical, 2)
            .background(
                isSelected ? Color.effectiveAccent : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
    }
    
    
    var body: some View {
        
        Form {
            Defaults.Toggle(key: .showDock) {
                Text("Show Dock")
            }
            Defaults.Toggle(key: .showDockLabels) {
                Text("Show Dock labels")
            }
            //slider for max items per column
            HStack {
                Stepper(value: $maxItemsPerColumn, in: 2...5) {
                    HStack {
                        Text("Max items per column")
                        Spacer()
                        Text("\(maxItemsPerColumn)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
                Section {
                List {
                    ForEach(dockItems, id: \.self) { dockItem in
                        DockItemRow(
                            dockItem: dockItem,
                            isSelected: selectedListDockItem == dockItem
                        )
                        .onTapGesture {
                            selectedListDockItem =
                                selectedListDockItem == dockItem ? nil : dockItem
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            imageUrl = ""
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListDockItem != nil {
                                let dockItem = selectedListDockItem!
                                selectedListDockItem = nil
                                dockItems.remove(
                                    at: dockItems.firstIndex(of: dockItem)!)
                                
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if let selected = selectedListDockItem {
                                currentEditingDockItem = selected
                                name = selected.name
                                url = selected.url.absoluteString
                                imageUrl = selected.imageURL?.absoluteString ?? ""
                                isPresented.toggle()
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                                
                                .accessibility(label: Text("Edit"))
                        }
                        Divider()
                        Button {
                                
                            let index = dockItems.firstIndex(of: selectedListDockItem!)
                            if index != nil && index! > 0 {
                                dockItems.swapAt(index!, index! - 1)
                            }
                            
                        }
                        label: {
                            Image(systemName: "arrow.up")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                                .accessibility(label: Text("Reorder Up"))
                        }
                        Button {
                            let index = dockItems.firstIndex(of: selectedListDockItem!)
                            if index != nil && index! < dockItems.count - 1 {
                                dockItems.swapAt(index!, index! + 1)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                                .accessibility(label: Text("Reorder Down"))
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if dockItems.isEmpty {
                        Text("No dock item yet")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new dock item")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        if (!imageUrl.isEmpty) {
                            KFImage(URL(string:imageUrl))
                                .placeholder {
                                    ProgressView()
                                }
                                .onFailure { error in
                                    print("Image failed:", error)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        TextField("Name", text: $name)
                        TextField("URL", text: $url)
                            .onChange(of: url) { newValue in
                                    fetchTask?.cancel()
                                    
                                    fetchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                                        
                                        guard let urlValue = URL(string: newValue) else { return }
                                        
                                        if let fetchedImageURL = await fetchOGImage(from: urlValue) {
                                            imageUrl = fetchedImageURL.absoluteString
                                        }
                                    }
                                }
                        TextField("Image URL", text: $imageUrl)
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            
                            Button {
                                if let editingItem = currentEditingDockItem,
                                      let index = dockItems.firstIndex(of: editingItem) {
                                    dockItems.remove(at: index)
                                }
                                
                                
                                let dockItem: DockItem = .init(
                                    id: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    imageURL: URL(string: imageUrl),
                                )
                                
                                if !dockItems.contains(dockItem) {
                                    dockItems.append(dockItem)
                                }
                                
                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Dock items")
                    if !Defaults[.dockItems].isEmpty {
                        Text(" – \(Defaults[.dockItems].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
        }
        
        
    }
}
