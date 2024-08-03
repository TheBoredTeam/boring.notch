//
//  BuyMeCoffee.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI
import Foundation

struct BuyMeCoffee:View {
    var body: some View {
        VStack {
                   Button(action: {
                       // Open "Buy Me a Coffee" URL
                       if let url = URL(string: "https://www.buymeacoffee.com/yourusername") {
                           NSWorkspace.shared.open(url)
                       }
                   }) {
                       HStack {
                           Image(systemName: "cup.and.saucer.fill") // Coffee cup icon
                               .font(.system(size: 10))
                           Text("Buy Me a Coffee")
                               .font(.system(size: 10))
                       }.padding(
                        .horizontal, 4).padding(.vertical, 6)
                       .background(Color.white) // Background color
                       .foregroundColor(.black) // Text color
                       .cornerRadius(8) // Rounded corners
                       .shadow(radius: 5) // Shadow effect
                   }
                   .buttonStyle(PlainButtonStyle()) // Ensure default button styling is overridden
               }

    }
}
