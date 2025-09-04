//
//  BackgroundManager.swift
//  boringNotch
//
//  Created by Adon Omeri on 4/9/2025.
//

import Defaults
import SwiftUI

@MainActor
class BackgroundManager: ObservableObject {
	static let shared = BackgroundManager()

	private init() {}

	var background: some View {
		switch Defaults[.background] {
		case .black:
			return AnyView(
				Color.black
			)

		case .ultraThinMaterial:
			return AnyView(
				Color.clear
					.background(.ultraThinMaterial)
			)
		}
	}
}
