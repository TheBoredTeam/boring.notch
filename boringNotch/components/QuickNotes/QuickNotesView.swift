import SwiftUI

struct QuickNotesView: View {
    @ObservedObject var manager = QuickNotesManager.shared
    @State private var showCopiedCheckmark = false
    
    var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack {
                Label("Quick Notes", systemImage: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                // Copy Button
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(manager.text, forType: .string)
                    
                    withAnimation {
                        showCopiedCheckmark = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedCheckmark = false
                        }
                    }
                }) {
                    Image(systemName: showCopiedCheckmark ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(showCopiedCheckmark ? .green : .white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy to Clipboard")
                
                // Clear Button
                Button(action: {
                    withAnimation {
                        manager.text = ""
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear Notes")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            // Text Editor Area
            ZStack(alignment: .topLeading) {
                if manager.text.isEmpty {
                    Text("Jot something down...")
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.leading, 15)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: .init(
                    get: { manager.text },
                    set: { manager.text = $0 }
                ))
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden) 
                .background(Color.clear)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { isHovering in
            if !isHovering {
                NSCursor.arrow.set()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
}
