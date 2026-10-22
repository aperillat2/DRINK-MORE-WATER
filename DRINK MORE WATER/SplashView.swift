import SwiftUI

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
    SplashView()
}
