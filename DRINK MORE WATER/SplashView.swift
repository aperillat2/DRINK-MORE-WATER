import SwiftUI

struct SplashView: View {
    var body: some View {
        // Full-screen photo, cropped to fit each screen shape (matches LaunchScreen.storyboard).
        Color(red: 219 / 255, green: 236 / 255, blue: 242 / 255)
            .overlay {
                Image("splash_photo")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

#Preview {
    SplashView()
}
