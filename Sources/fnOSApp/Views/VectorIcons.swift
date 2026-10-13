import SwiftUI

// MARK: - 纯矢量高质感图标集合 (严禁使用任何 Emoji)

public struct OctocatIcon: View {
    public var size: CGFloat = 13
    public var color: Color = .white.opacity(0.85)

    public init(size: CGFloat = 13, color: Color = Color.white.opacity(0.85)) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let path = Path { p in
                // Standard GitHub Octocat Silhouette SVG Path scaled to canvas
                let scale = size.width / 24.0
                p.move(to: CGPoint(x: 12 * scale, y: 0))
                // Approximate smooth path
                p.addEllipse(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

public struct LogoBadgeView: View {
    public var size: CGFloat = 20

    private static let cachedLogoImage: NSImage? = {
        if let path = Bundle.main.path(forResource: "AppLogo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSApp.applicationIconImage
    }()

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        if let nsImg = Self.cachedLogoImage {
            Image(nsImage: nsImg)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .shadow(color: Color.cyan.opacity(0.28), radius: max(2, size * 0.12), x: 0, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.0, green: 0.32, blue: 0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Image(systemName: "server.rack")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}
