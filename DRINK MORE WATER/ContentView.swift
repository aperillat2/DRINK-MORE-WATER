//
//  ContentView.swift
//  DRINK MORE WATER
//
//  Created by AARON PERILLAT on 10/22/25.
//
import SwiftUI

struct ContentView: View {
    private let glassVerticalNudge: CGFloat = -6
    private let textScale: CGFloat = 0.54
    private let textOffset: CGSize = CGSize(width: 0, height: 58)

    var body: some View {
        ZStack {
            Color(.systemBlue)

            ZStack {
                Image("glass_text")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 551, height: 722)
                    .scaleEffect(textScale)
                    .offset(y: glassVerticalNudge)
                    .offset(x: textOffset.width, y: textOffset.height)
                    .accessibilityHidden(true)

                Image("empty_glass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 551, height: 722)
                    .offset(y: glassVerticalNudge)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBlue)

            Image("drink_more_water")
                .resizable()
                .scaledToFit()
                .frame(width: 551, height: 722)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
