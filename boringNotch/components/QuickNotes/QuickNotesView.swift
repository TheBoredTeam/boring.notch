import SwiftUI

struct QuickNotesView: View {
    @ObservedObject var manager = QuickNotesManager.shared
    
    var body: some View {
        VStack {
            TextEditor(text: .init(
                get: { manager.text },
                set: { manager.text = $0 }
            ))
            .font(.system(.body, design: .rounded))
            .scrollContentBackground(.hidden) 
            .background(Color.clear)
            .foregroundColor(.white)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
}
