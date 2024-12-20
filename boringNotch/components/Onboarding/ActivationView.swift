//
//  OnboardingSettings.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

struct ActivationWindow_Previews: PreviewProvider {
    static var previews: some View {
        ActivationWindow()
            .previewLayout(.sizeThatFits)
            .padding()
    }
}

struct ActivationWindow: View {
    @State private var email: String = ""
    @State private var key: String = ""
    var body: some View {
        VStack {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .padding(.top, 30)
                .padding(.bottom, 10)
            Text("activation.header.title")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
            Text("activation.header.subtitle")
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.bottom, 20)
            Group {
                TextField("activation.process.email", text: $email)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                TextField("activation.process.key", text: $key)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .textFieldStyle(PlainTextFieldStyle())
            .scrollContentBackground(.hidden)
            .toggleStyle(.switch)
            Spacer()
            VStack(alignment: .center, spacing: 14) {
                HStack(alignment: .center) {
                    HStack {
                        Button {} label: {
                            Text("common.cancel")
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(AccessoryBarButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image("theboringteam")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                        .offset(y: 4)
                        .blendMode(.overlay)
                    HStack {
                        Button {} label: {
                            Text("activation.process.activate")
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    
                }
                .controlSize(.extraLarge)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
        .frame(width: 350, height: 350)
    }
}
