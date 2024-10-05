//
//  OnboardingSettings.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

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
            Text("Activate your license")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
            Text("Transform your notch truly yours")
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.bottom, 20)
            Group {
                TextField("Email address", text: $email)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                TextField("License key", text: $key)
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
                            Text("Cancel")
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
                            Text("Activate")
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
