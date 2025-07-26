//
//  WelcomeView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI
import SwiftUIIntrospect

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil
    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Image("spotlight")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.bottom)
                    .blur(radius: 3)
                    .offset(y: -5)
                    .background(SparkleView().opacity(0.6))
                VStack(spacing: 8) {
                    Image("logo2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .padding(.bottom, 8)
                    Text("Boring Notch")
                        .font(.system(.largeTitle, design: .default))
                        .fontWeight(.semibold)
                    Text("Welcome")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 30)
                    if false {
                        Text("PRO")
                            .font(.system(size: 18, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.7), location: 0.3), .init(color: .clear, location: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .blendMode(.overlay)
                            )
                            .padding(.bottom, 30)
                    }


                    Button {
                        onGetStarted?()
                    } label: {
                        Text("Get started")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
                .padding(.top)
            }
            
            Image("theboringteam")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding()
                .padding(.bottom, 36)
                .blendMode(.overlay)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    WelcomeView()
}
