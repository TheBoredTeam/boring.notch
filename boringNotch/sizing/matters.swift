//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Foundation

var notchClosedWidth: CGFloat = 200

struct Area {
    var width: CGFloat?
    var height: CGFloat?
    var inset: CGFloat?
}

struct StatesSizes {
    var opened: Area
    var closed: Area
}

struct Sizes {
    var corderRadius: StatesSizes = StatesSizes(opened: Area(inset: 24), closed: Area(inset:10))
    var size: StatesSizes = StatesSizes(
        opened:Area(width: 500, height: 220),
        closed:Area(width: notchClosedWidth, height: 40)
    )
}

struct MusicPlayerElementSizes {
    
    var baseSize: Sizes = Sizes()
    
    var image: Sizes = Sizes(
        corderRadius: StatesSizes(
            opened: Area(inset: 14), closed: Area(inset:4)),
        size: StatesSizes(
            opened: Area(width: 70, height: 70), closed: Area(width: 20, height: 20)
        )
    )
    var player: Sizes = Sizes(
        size: StatesSizes(
            opened: Area(width: 430), closed: Area(width: notchClosedWidth)
        )
    )
}
