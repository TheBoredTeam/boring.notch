//
//  ShelfView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI

struct ShelfView: View {
    let dropInteraction: DropInteractionState
    let animation: Animation?

    var body: some View {
        HStack(spacing: 12) {
            FileShareView(dropInteraction: dropInteraction)
                .aspectRatio(1, contentMode: .fit)
            ShelfDropWell(
                dropInteraction: dropInteraction,
                animation: animation,
                showsShelvedItems: true
            )
        }
    }
}
