//
//  HelloAnimation.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/08/24.
//

import SwiftUI

struct HelloAnimation: View {
    var body: some View {
        HellowView()
            .phaseAnimator([false, true]) { hello, draw in
                HellowView()
                    .trim(from: 0.0, to: draw ? 1 : 0.0 )
                    .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .fill(LinearGradient(gradient: Gradient(colors: [.red, .blue, .green]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.vertical, 60)
            } animation: { draw in
                    .spring(duration: 3).repeatForever(autoreverses: true)
            }
    }
}

struct HellowView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.00095*width, y: 0.88718*height))
        path.addCurve(to: CGPoint(x: 0.19536*width, y: 0.31015*height), control1: CGPoint(x: 0.00993*width, y: 0.87738*height), control2: CGPoint(x: 0.16556*width, y: 0.56785*height))
        path.addCurve(to: CGPoint(x: 0.15043*width, y: 0.04964*height), control1: CGPoint(x: 0.22517*width, y: 0.05245*height), control2: CGPoint(x: 0.1859*width, y: -0.068*height))
        path.addCurve(to: CGPoint(x: 0.10028*width, y: 0.932*height), control1: CGPoint(x: 0.11495*width, y: 0.16729*height), control2: CGPoint(x: 0.09792*width, y: 1.02023*height))
        path.addCurve(to: CGPoint(x: 0.18354*width, y: 0.47822*height), control1: CGPoint(x: 0.10265*width, y: 0.84376*height), control2: CGPoint(x: 0.12157*width, y: 0.47822*height))
        path.addCurve(to: CGPoint(x: 0.22327*width, y: 0.88718*height), control1: CGPoint(x: 0.25733*width, y: 0.51463*height), control2: CGPoint(x: 0.19915*width, y: 0.81575*height))
        path.addCurve(to: CGPoint(x: 0.38553*width, y: 0.71351*height), control1: CGPoint(x: 0.2474*width, y: 0.95861*height), control2: CGPoint(x: 0.33586*width, y: 0.89978*height))
        path.addCurve(to: CGPoint(x: 0.35998*width, y: 0.45441*height), control1: CGPoint(x: 0.43519*width, y: 0.52724*height), control2: CGPoint(x: 0.38978*width, y: 0.4306*height))
        path.addCurve(to: CGPoint(x: 0.35478*width, y: 0.87317*height), control1: CGPoint(x: 0.33018*width, y: 0.47822*height), control2: CGPoint(x: 0.27956*width, y: 0.71631*height))
        path.addCurve(to: CGPoint(x: 0.53453*width, y: 0.62808*height), control1: CGPoint(x: 0.42999*width, y: 1.03004*height), control2: CGPoint(x: 0.51892*width, y: 0.6939*height))
        path.addCurve(to: CGPoint(x: 0.57332*width, y: 0.00623*height), control1: CGPoint(x: 0.55014*width, y: 0.56225*height), control2: CGPoint(x: 0.63955*width, y: 0.05805*height))
        path.addCurve(to: CGPoint(x: 0.48723*width, y: 0.60146*height), control1: CGPoint(x: 0.5071*width, y: -0.04559*height), control2: CGPoint(x: 0.48486*width, y: 0.50623*height))
        path.addCurve(to: CGPoint(x: 0.54588*width, y: 0.91239*height), control1: CGPoint(x: 0.48959*width, y: 0.6967*height), control2: CGPoint(x: 0.50378*width, y: 0.87597*height))
        path.addCurve(to: CGPoint(x: 0.70719*width, y: 0.51043*height), control1: CGPoint(x: 0.58798*width, y: 0.9488*height), control2: CGPoint(x: 0.6807*width, y: 0.64768*height))
        path.addCurve(to: CGPoint(x: 0.73273*width, y: 0.01323*height), control1: CGPoint(x: 0.73368*width, y: 0.37317*height), control2: CGPoint(x: 0.76679*width, y: 0.03984*height))
        path.addCurve(to: CGPoint(x: 0.67171*width, y: 0.15048*height), control1: CGPoint(x: 0.69868*width, y: -0.01338*height), control2: CGPoint(x: 0.68259*width, y: 0.07205*height))
        path.addCurve(to: CGPoint(x: 0.69678*width, y: 0.92639*height), control1: CGPoint(x: 0.66083*width, y: 0.22892*height), control2: CGPoint(x: 0.62204*width, y: 0.86057*height))
        path.addCurve(to: CGPoint(x: 0.87275*width, y: 0.47822*height), control1: CGPoint(x: 0.77152*width, y: 0.99222*height), control2: CGPoint(x: 0.78855*width, y: 0.42997*height))
        path.addCurve(to: CGPoint(x: 0.91438*width, y: 0.89776*height), control1: CGPoint(x: 0.9734*width, y: 0.51043*height), control2: CGPoint(x: 0.92329*width, y: 0.85998*height))
        path.addCurve(to: CGPoint(x: 0.79943*width, y: 0.69608*height), control1: CGPoint(x: 0.87047*width, y: 1.08403*height), control2: CGPoint(x: 0.77956*width, y: height))
        path.addCurve(to: CGPoint(x: 0.92006*width, y: 0.53081*height), control1: CGPoint(x: 0.81523*width, y: 0.45436*height), control2: CGPoint(x: 0.86282*width, y: 0.43277*height))
        path.addCurve(to: CGPoint(x: 0.99905*width, y: 0.432*height), control1: CGPoint(x: 0.95979*width, y: 0.57703*height), control2: CGPoint(x: 0.98959*width, y: 0.4944*height))
        return path
    }
}

#Preview {
    HelloAnimation().frame(width: 300, height: 220)
}
