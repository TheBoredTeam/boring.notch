//
//  MarqueeTextView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

struct Marquee: View {
    @State var text: String
    var font: Font
    
    @State var storedSize: CGSize = .zero
    @State var offset: CGFloat = 0
    
    var body: some View{
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(font)
                .offset(x: offset)
        }
        .disabled(true)
        .onAppear {
            storedSize = textSize()
            
            (1...15).forEach {_ in
                text.append(" ")
            }
            
            let timing: Double = (0.02 * storedSize.width)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.linear(duration: timing)){
                    offset = -storedSize.width
                }
            }
        }
        .onReceive(Timer.publish(every: (0.02 * storedSize.width), on: .main, in: .default).autoconnect(), perform: { _ in
            offset = 0
            withAnimation(.linear(duration: (0.02 * storedSize.width))) {
                offset = -storedSize.width
            }
        })
    }
    
    func textSize() -> CGSize {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        
        return size
    }
}
