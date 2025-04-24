//
//  NotchClipboardView.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 23/04/25.
//

import SwiftUI

struct NotchClipboardView : View {
    
    private var data  = Array(1...20)
       private let gridRows = [
        GridItem(.adaptive(minimum: 200)),
        //GridItem(.adaptive(minimum: 10))
       ]
    
    var body: some View {
        ScrollView(.horizontal){
            LazyHGrid(rows: gridRows, spacing: 20)  {
                            ForEach(data, id: \.self) { item in
                                //ClipboardTile(text: item.description)
                }
            }
        }
        /*HStack{
            ClipboardTile();
            ClipboardTile()
        }*/
        
        
    }
}

#Preview {
    NotchClipboardView()
}
