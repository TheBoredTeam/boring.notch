//
//  CapsLockIndicatorView.swift
//  boringNotch
//
//  Created by Lucas Walker on 5/11/26.
//

import SwiftUI

struct CapsLockIndicatorView: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: "capslock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            HStack {
                Spacer(minLength: 0)
                Text("Caps Lock")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10)
        }
        .frame(height: vm.closedNotchSize.height, alignment: .center)
    }
}

#Preview {
    CapsLockIndicatorView()
        .frame(width: 360)
        .background(Color.black)
        .environmentObject(BoringViewModel())
}
