//
//  HoverLockButton.swift
//  boringNotch
//
//  Created by Adon Omeri on 3/9/2025.
//

import SwiftUI

struct HoverLockButton: View {
	@EnvironmentObject var vm: BoringViewModel

	var body: some View {
		ZStack {
			Button {
				vm.lockOpen.toggle()
			} label: {
				Capsule()
					.fill(.black)
					.frame(width: 30, height: 30)
					.overlay {
						Image(systemName: vm.lockOpen ? "lock" : "lock.open")
							.contentTransition(.symbolEffect(.replace.offUp))
							.imageScale(.medium)
							.labelStyle(.iconOnly)
							.padding(3)
							.background(vm.lockOpen ? Color.blue.opacity(0.5) : Color.clear)
							.clipShape(RoundedRectangle(cornerRadius: 8))
							.foregroundColor(.white)
					}
			}
			.buttonStyle(.plain)
			.animation(.easeInOut(duration: 0.3), value: vm.lockOpen)
		}
	}
}
