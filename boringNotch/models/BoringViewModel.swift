//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import SwiftUI
import Combine

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
    var corderRadius: StatesSizes = StatesSizes(opened: Area(inset: 20), closed: Area(inset:10))
    var size: StatesSizes = StatesSizes(
        opened:Area(width: 500, height: 220),
        closed:Area(width: 300, height: 40)
    )
}

struct MusicPlayerElementSizes {
    var image: Sizes = Sizes(
        corderRadius: StatesSizes(
            opened: Area(inset: 14), closed: Area(inset:4)),
        size:StatesSizes(
            opened: Area(width: 80, height: 80), closed: Area(width:20, height: 20)
        )
    )
}

class BoringViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    
    let animationLibrary:BoringAnimations = BoringAnimations()
    let animation:Animation?
    @Published var contentType: ContentType = .normal
    @Published var notchState: NotchState = .closed
    @Published var currentView: NotchViews = .empty
    @Published var headerTitle: String = "Boring Notch"
    @Published var emptyStateText: String = "Play some jams, ladies, and watch me shine! New features coming soon! 🎶 🚀"
    @Published var sizes : Sizes = Sizes()
    @Published var musicPlayerSizes: MusicPlayerElementSizes = MusicPlayerElementSizes()
    @Published var waitInterval: Double = 10
    @Published var releaseName:String = "Beautiful Sheep"
    
    deinit {
        destroy()
    }
    
    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    
    override
    init() {
        self.animation = self.animationLibrary.animation
        super.init()
    }
    
    func open(){
        self.notchState = .open
    }
    
    func close(){
        self.notchState = .closed
    }
    
    func openMenu(){
        self.currentView = .menu
    }
    
    func openMusic(){
        self.currentView = .music
    }
    
    func showEmpty() {
        self.currentView = .empty
    }
}

