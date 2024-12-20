//
//  WhatsNewView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI

struct WhatsNewView: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("changelog.whats_new")
                .font(.largeTitle)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("• New feature 1")
                Text("• Improved performance")
                Text("• Bug fixes")
            }
            
            Button("changelog.got_it") {
                isPresented = false
            }
        }
        .frame(width: 300, height: 200)
        .padding()
    }
}

#Preview {
    WhatsNewView(isPresented: .constant(true))
}
