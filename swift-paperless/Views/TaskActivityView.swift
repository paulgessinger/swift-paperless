//
//  TaskActivityView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import SwiftUI

struct TaskActivityView: View {
    let text: String
    let color: Color = .accentColor

    @State private var trimFrom = 0.0
    @State private var trimTo = 0.25
    @State private var rotation = -90.0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: trimFrom, to: trimTo)
                .stroke(color, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(rotation))
                .frame(width: 23, height: 23)
            Text(text)
                .foregroundColor(color)
                .frame(width: 19, height: 19)
                .scaledToFit()
                .monospacedDigit()
                .minimumScaleFactor(0.2)
                .lineLimit(1)
        }
        .task {
            // @TODO: Refactor animation once we have keyframe animations
            let duration = 1.0
            repeat {
                withAnimation(.linear(duration: duration)) {
                    rotation = 90
                    trimTo = 1.0
                }
                try? await Task.sleep(for: .seconds(duration))
                rotation = 90
                trimTo = 1.0
                withAnimation(.linear(duration: duration)) {
                    rotation = 270
                    trimFrom = 1.0
                }
                try? await Task.sleep(for: .seconds(duration))
                trimFrom = 0.0
                trimTo = 0.0
                withAnimation(.easeIn(duration: duration / 4)) {
                    trimTo = 0.25
                }
                try? await Task.sleep(for: .seconds(duration / 4))
                trimFrom = 0.0
                trimTo = 0.25
                rotation = -90
            } while !Task.isCancelled
        }
    }
}

struct TaskActivityView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Text(String("Body"))
                .navigationTitle(String("Title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
//                        Menu {
//                            Text("Bli bla blubb")
//                            Divider()
//                            Text("Bli bla blubb")
//                        } label: {
                        VStack {
                            TaskActivityView(text: "9")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String("GOGO")) {}
                    }
                }
        }
    }
}
