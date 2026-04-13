//
//  SteadyCheckInView.swift
//  spruceNotch
//

import SwiftUI

struct SteadyCheckInView: View {
    @ObservedObject private var manager = SteadyCheckInManager.shared
    @EnvironmentObject private var vm: SpruceViewModel

    var body: some View {
        reminderContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 4)
    }

    private var reminderContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steady check-in")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Time for your daily check-in.")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Button("Open Steady") {
                    manager.openSteadyApp()
                    manager.markCompletedAndDismiss()
                    vm.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Button("Ignore today") {
                    manager.ignoreFlow()
                    vm.close()
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
