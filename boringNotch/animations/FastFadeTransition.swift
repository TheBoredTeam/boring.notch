	//
	//  View+.swift
	//  boringNotch
	//
	//  Created by Adon Omeri on 31/8/2025.
	//

import SwiftUI

extension View {
	func fastFadeTransition() -> some View {
		self.transition(.asymmetric(
			insertion: .opacity,
			removal: .opacity
		))
	}
}

