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
	let vm = BoringViewModel()

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

		case .blur:

				if #available(macOS 26.0, *) {
					return AnyView(
					Color.clear
						.glassEffect(.clear, in: Rectangle())
					)
				} else {
					return AnyView(
					Color.clear
					)
				}

		}
	}
}
