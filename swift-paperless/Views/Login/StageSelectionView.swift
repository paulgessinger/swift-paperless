//
//  StageSelectionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import SwiftUI

struct StageSelection: View {
  @Binding var stage: LoginStage

  @Namespace private var animation

  var body: some View {
    HStack {
      ForEach(LoginStage.allCases, id: \.self) { el in
        if el == stage {
          el.label
            .foregroundStyle(Color.accentColor)
            .matchedGeometryEffect(id: el, in: animation)
            .padding(.bottom, 3)
            .background(alignment: .bottom) {
              RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor)
                .frame(height: 3)
                .matchedGeometryEffect(id: "active", in: animation)
            }
        } else {
          el.label
            .onTapGesture {
              if el < stage {
                stage = el
              }
            }
            .matchedGeometryEffect(id: el, in: animation)
        }
      }
    }

    .animation(.spring(duration: 0.25, bounce: 0.25), value: stage)

    .padding(.vertical, 10)
    .padding(.horizontal)
    .background(
      Capsule()
        .fill(.thickMaterial)
        .stroke(.tertiary)
        .shadow(color: Color(white: 0.2, opacity: 0.1), radius: 10)
    )
  }
}
