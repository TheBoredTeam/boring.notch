import SwiftUI

private enum MuteIndicatorSide {
    case leading
    case trailing
}

private struct MuteIndicatorEdge: View {
    let side: MuteIndicatorSide
    let isMuted: Bool
    let notchState: NotchState
    let closedNotchHeight: CGFloat
    let burstTrigger: UInt
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstScale: CGFloat = 0.82
    @State private var burstOpacity: Double = 0
    
    private var sizeScale: CGFloat {
        let clampedHeight = min(max(closedNotchHeight, 16), 40)
        return clampedHeight / 32
    }
    
    private var edgeWidth: CGFloat {
        min(max(2.7 * sizeScale, 1.9), 4.1)
    }
    
    private var sideInset: CGFloat {
        min(max(1.5 * sizeScale, 0.9), 2.4)
    }
    
    private var glowWidth: CGFloat {
        edgeWidth + 5.1
    }
    
    private var hiddenScale: CGFloat {
        reduceMotion ? 1 : 0.95
    }
    
    private var visibilityScale: CGFloat {
        if reduceMotion { return 1 }
        return isVisible ? 1 : 1.12
    }
    
    private var lowerTailHeight: CGFloat {
        min(max(4.8 * sizeScale, 3.2), 7.2)
    }
    
    private var lowerTailDrop: CGFloat {
        min(max(1.1 * sizeScale, 0.7), 1.8)
    }
    
    private var alignment: Alignment {
        side == .leading ? .leading : .trailing
    }
    
    private var gradientStart: UnitPoint {
        side == .leading ? .leading : .trailing
    }
    
    private var gradientEnd: UnitPoint {
        side == .leading ? .trailing : .leading
    }
    
    private var hiddenAnchor: UnitPoint {
        side == .leading ? .leading : .trailing
    }
    
    private let mutedRed = Color(red: 0.95, green: 0.20, blue: 0.24)
    
    private var isVisible: Bool {
        notchState == .closed
    }
    
    private var shouldRender: Bool {
        isMuted && isVisible
    }
    
    var body: some View {
        ZStack(alignment: alignment) {
            if !reduceMotion {
                Capsule()
                    .fill(mutedRed.opacity(0.42))
                    .frame(width: glowWidth)
                    .frame(maxHeight: .infinity)
                    .blur(radius: 5.2)
                    .scaleEffect(x: burstScale, y: 1, anchor: hiddenAnchor)
                    .opacity(burstOpacity)
            }
            
            ZStack(alignment: alignment) {
                LinearGradient(
                    colors: [
                        mutedRed.opacity(0.98),
                        Color(red: 0.81, green: 0.12, blue: 0.15).opacity(0.92),
                        Color(red: 0.45, green: 0.04, blue: 0.08).opacity(0.38)
                    ],
                    startPoint: gradientStart,
                    endPoint: gradientEnd
                )
                .frame(width: glowWidth)
                
                Rectangle()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: 0.95)
                    .blur(radius: 0.2)
            }
            .frame(maxHeight: .infinity)
            .shadow(color: mutedRed.opacity(0.64), radius: 5.1, x: 0, y: 0)
            
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            mutedRed.opacity(0.02),
                            mutedRed.opacity(0.52)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: glowWidth + 1.2, height: lowerTailHeight)
                .blur(radius: 1.05)
                .offset(y: lowerTailDrop)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(side == .leading ? .leading : .trailing, sideInset)
        .opacity(shouldRender ? 1 : 0)
        .scaleEffect(
            x: (isMuted ? 1 : hiddenScale) * visibilityScale,
            y: visibilityScale,
            anchor: hiddenAnchor
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.14)
                : (isMuted ? StandardAnimations.muteBadgeIn : StandardAnimations.muteBadgeOut),
            value: isMuted
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.14)
                : (notchState == .open ? StandardAnimations.open : StandardAnimations.close),
            value: notchState
        )
        .onChange(of: burstTrigger) { _, _ in
            triggerBurst()
        }
        .accessibilityHidden(true)
    }
    
    private func triggerBurst() {
        guard isMuted, !reduceMotion else { return }
        
        burstScale = 0.82
        burstOpacity = 0.58
        
        withAnimation(StandardAnimations.muteBadgeBurst) {
            burstScale = 1.55
            burstOpacity = 0
        }
    }
}

struct MuteIndicatorEdges: View {
    let isMuted: Bool
    let notchState: NotchState
    let closedNotchHeight: CGFloat
    let burstTrigger: UInt
    
    var body: some View {
        ZStack {
            MuteIndicatorEdge(
                side: .leading,
                isMuted: isMuted,
                notchState: notchState,
                closedNotchHeight: closedNotchHeight,
                burstTrigger: burstTrigger
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            
            MuteIndicatorEdge(
                side: .trailing,
                isMuted: isMuted,
                notchState: notchState,
                closedNotchHeight: closedNotchHeight,
                burstTrigger: burstTrigger
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}
