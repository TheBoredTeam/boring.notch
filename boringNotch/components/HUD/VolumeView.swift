//
//  VolumeView.swift
//  boringNotch
//
//  Created by Alessandro Gravagno on 24/03/25.
//



import SwiftUI

struct VolumeView: View {
    @ObservedObject var volumeObserver: VolumeChangeObserver
    
    private var notchWidth: CGFloat
    
    init(volumeObserver: VolumeChangeObserver, notchWidth: CGFloat) {
        self.volumeObserver = volumeObserver
        self.notchWidth = notchWidth
    }
    
    
    var body: some View {
        HStack{
            Image(systemName: volumeObserver.isInternal ? iconForVolume(volumeObserver.currentVolume) : "headphones") // if the output's device is different from internal speaker, we use headphones icon
                .font(.caption)
                .foregroundColor(.white)
            ProgressView(
                value: Double(volumeObserver.currentVolume ?? 0.0), total: 1.0
            )
            .progressViewStyle(CustomProgressViewStyle(progressColor: .white, width: self.notchWidth - 50))
            .padding()
            .frame(width: self.notchWidth - 50, height: 20)
        }.frame(maxWidth: self.notchWidth, maxHeight: .infinity, alignment: .center)
        
    }
    
    // Create a custom progress view style
    
    struct CustomProgressViewStyle: ProgressViewStyle {
        var progressColor: Color
        var width: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            ZStack(alignment: Alignment.leading) {
                // Barra di sfondo
                            RoundedRectangle(cornerRadius: 10)
                                .frame(width: width, height: 4)
                                .foregroundColor(Color.gray.opacity(0.3))
                            
                            // Barra del progresso che si espande verso destra
                            RoundedRectangle(cornerRadius: 10)
                                .frame(width: CGFloat(configuration.fractionCompleted ?? 0) * width, height: 4)
                                .foregroundColor(progressColor)
                                .animation(.easeInOut(duration: 0.2), value: configuration.fractionCompleted)
                        
            }
        }
    }
    
    // Change icon based on actual volume level
    func iconForVolume(_ volume: Float?) -> String {
        guard let volume = volume else { return "speaker.fill" }
        
        switch volume {
        case 0.0:
            return "speaker.slash.fill"
        case 0.01..<0.34:
            return "speaker.1.fill"
        case 0.34..<0.67:
            return "speaker.2.fill"
        case 0.67...1.0:
            return "speaker.3.fill"
        default:
            return "speaker.fill"
        }
    }
}

