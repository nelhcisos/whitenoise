import CoreGraphics
import UIKit

/// Pictures for the browser demo, drawn in code: no assets and no text.
/// Plain Core Graphics, so it can run off the main thread inside DemoBackend.
enum DemoArt {
    enum Scene: CaseIterable {
        case sunset, sea, night, coffee, hills
    }

    /// A generated square photo for the camera when the simulator has none. Varies per call.
    @MainActor static func samplePhoto() -> UIImage {
        let scene = Scene.allCases.randomElement() ?? .sunset
        return image(scene, seed: UInt64.random(in: 1...1_000_000))
    }

    /// JPEG bytes of one scene: the demo stores photos as files, like uploads.
    static func jpeg(_ scene: Scene, seed: UInt64) -> Data {
        image(scene, seed: seed).jpegData(compressionQuality: 0.8) ?? Data()
    }

    /// Same scene and seed give the same picture.
    static func image(_ scene: Scene, seed: UInt64) -> UIImage {
        let side = 1080
        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return UIImage() }
        // Top-left origin, like UIKit.
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        var rng = SeededGenerator(seed: seed)
        let size = CGFloat(side)
        switch scene {
        case .sunset: drawSunset(ctx, size, &rng)
        case .sea: drawSea(ctx, size, &rng)
        case .night: drawNight(ctx, size, &rng)
        case .coffee: drawCoffee(ctx, size, &rng)
        case .hills: drawHills(ctx, size, &rng)
        }
        guard let cgImage = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Scenes

    private static func drawSunset(_ ctx: CGContext, _ s: CGFloat, _ rng: inout SeededGenerator) {
        let warm = CGFloat.random(in: 0...0.15, using: &rng)
        gradient(ctx, from: color(1, 0.55 + warm, 0.35), to: color(0.95, 0.35, 0.55), height: s)
        fillCircle(ctx, color(1, 0.86, 0.35), center: CGPoint(x: s * CGFloat.random(in: 0.3...0.7, using: &rng), y: s * 0.55), radius: s * 0.13)
        skyline(ctx, s, base: s, color: color(0.17, 0.11, 0.23), rng: &rng, windows: nil)
    }

    private static func drawSea(_ ctx: CGContext, _ s: CGFloat, _ rng: inout SeededGenerator) {
        gradient(ctx, from: color(0.49, 0.78, 0.91), to: color(0.78, 0.91, 0.97), height: s * 0.6)
        fillCircle(ctx, color(1, 0.84, 0.3), center: CGPoint(x: s * CGFloat.random(in: 0.2...0.8, using: &rng), y: s * 0.3), radius: s * 0.09)
        ctx.setFillColor(color(0.12, 0.5, 0.7))
        ctx.fill(CGRect(x: 0, y: s * 0.6, width: s, height: s * 0.4))
        ctx.setStrokeColor(color(0.85, 0.95, 1))
        ctx.setLineWidth(s * 0.008)
        for row in 0..<5 {
            let y = s * (0.66 + CGFloat(row) * 0.07)
            let phase = CGFloat.random(in: 0...60, using: &rng)
            ctx.move(to: CGPoint(x: -phase, y: y))
            var x = -phase
            while x < s {
                ctx.addQuadCurve(to: CGPoint(x: x + s * 0.12, y: y), control: CGPoint(x: x + s * 0.06, y: y - s * 0.025))
                x += s * 0.12
            }
            ctx.strokePath()
        }
    }

    private static func drawNight(_ ctx: CGContext, _ s: CGFloat, _ rng: inout SeededGenerator) {
        gradient(ctx, from: color(0.07, 0.09, 0.2), to: color(0.15, 0.17, 0.33), height: s)
        ctx.setFillColor(color(1, 1, 1))
        for _ in 0..<60 {
            let r = CGFloat.random(in: 1.5...4, using: &rng)
            ctx.fillEllipse(in: CGRect(x: CGFloat.random(in: 0...s, using: &rng), y: CGFloat.random(in: 0...(s * 0.5), using: &rng), width: r, height: r))
        }
        fillCircle(ctx, color(0.96, 0.93, 0.8), center: CGPoint(x: s * 0.75, y: s * 0.2), radius: s * 0.08)
        skyline(ctx, s, base: s, color: color(0.05, 0.06, 0.13), rng: &rng, windows: color(1, 0.78, 0))
    }

    private static func drawCoffee(_ ctx: CGContext, _ s: CGFloat, _ rng: inout SeededGenerator) {
        let tone = CGFloat.random(in: 0...0.08, using: &rng)
        ctx.setFillColor(color(0.55 + tone, 0.38 + tone, 0.25))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        // Saucer, cup, coffee, handle.
        fillEllipse(ctx, color(0.93, 0.92, 0.9), CGRect(x: s * 0.15, y: s * 0.22, width: s * 0.7, height: s * 0.62))
        fillEllipse(ctx, color(0.98, 0.98, 0.97), CGRect(x: s * 0.27, y: s * 0.32, width: s * 0.46, height: s * 0.42))
        fillEllipse(ctx, color(0.36, 0.22, 0.13), CGRect(x: s * 0.31, y: s * 0.36, width: s * 0.38, height: s * 0.34))
        fillEllipse(ctx, color(0.78, 0.6, 0.42), CGRect(x: s * 0.42, y: s * 0.46, width: s * 0.16, height: s * 0.12))
        ctx.setStrokeColor(color(0.98, 0.98, 0.97))
        ctx.setLineWidth(s * 0.04)
        ctx.addArc(center: CGPoint(x: s * 0.76, y: s * 0.53), radius: s * 0.07, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        ctx.strokePath()
    }

    private static func drawHills(_ ctx: CGContext, _ s: CGFloat, _ rng: inout SeededGenerator) {
        gradient(ctx, from: color(0.62, 0.84, 0.95), to: color(0.93, 0.96, 0.9), height: s * 0.7)
        fillCircle(ctx, color(1, 0.95, 0.75), center: CGPoint(x: s * 0.25, y: s * 0.22), radius: s * 0.07)
        let greens = [color(0.42, 0.66, 0.36), color(0.3, 0.55, 0.3), color(0.2, 0.42, 0.25)]
        for (index, green) in greens.enumerated() {
            let top = s * (0.48 + CGFloat(index) * 0.12)
            ctx.setFillColor(green)
            ctx.move(to: CGPoint(x: 0, y: s))
            ctx.addLine(to: CGPoint(x: 0, y: top + CGFloat.random(in: 0...(s * 0.08), using: &rng)))
            ctx.addQuadCurve(
                to: CGPoint(x: s, y: top + CGFloat.random(in: 0...(s * 0.08), using: &rng)),
                control: CGPoint(x: s * CGFloat.random(in: 0.2...0.8, using: &rng), y: top - s * 0.18)
            )
            ctx.addLine(to: CGPoint(x: s, y: s))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    // MARK: - Helpers

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static func gradient(_ ctx: CGContext, from top: CGColor, to bottom: CGColor, height: CGFloat) {
        let colors = [top, bottom] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: 10_000, height: height))
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    private static func fillCircle(_ ctx: CGContext, _ fill: CGColor, center: CGPoint, radius: CGFloat) {
        fillEllipse(ctx, fill, CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func fillEllipse(_ ctx: CGContext, _ fill: CGColor, _ rect: CGRect) {
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: rect)
    }

    /// Rooftops along the bottom edge; lit windows when `windows` is given.
    private static func skyline(_ ctx: CGContext, _ s: CGFloat, base: CGFloat, color fill: CGColor, rng: inout SeededGenerator, windows: CGColor?) {
        var x: CGFloat = 0
        while x < s {
            let width = s * CGFloat.random(in: 0.08...0.16, using: &rng)
            let height = s * CGFloat.random(in: 0.15...0.4, using: &rng)
            let rect = CGRect(x: x, y: base - height, width: width, height: height)
            ctx.setFillColor(fill)
            ctx.fill(rect)
            if let windows {
                ctx.setFillColor(windows)
                var wy = rect.minY + s * 0.03
                while wy < base - s * 0.04 {
                    var wx = rect.minX + s * 0.015
                    while wx < rect.maxX - s * 0.03 {
                        if Bool.random(using: &rng) {
                            ctx.fill(CGRect(x: wx, y: wy, width: s * 0.015, height: s * 0.02))
                        }
                        wx += s * 0.03
                    }
                    wy += s * 0.045
                }
            }
            x += width
        }
    }
}

/// Small deterministic generator (xorshift), so seeded pictures repeat.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = (seed &* 0x9E37_79B9_7F4A_7C15) | 1
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
