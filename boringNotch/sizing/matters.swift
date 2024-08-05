//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Foundation


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
        closed:Area(width: 320, height: 40)
    )
}

struct MusicPlayerElementSizes {
    var image: Sizes = Sizes(
        corderRadius: StatesSizes(
            opened: Area(inset: 14), closed: Area(inset:4)),
        size:StatesSizes(
            opened: Area(width: 70, height: 70), closed: Area(width:20, height: 20)
        )
    )
}
