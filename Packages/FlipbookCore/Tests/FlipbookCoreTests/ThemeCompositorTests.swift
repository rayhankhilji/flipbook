import CoreGraphics
import Foundation
import Testing

@testable import FlipbookCore

@Suite struct ThemeCompositorTests {
    /// Builds a solid-color test bitmap.
    private func makeImage(red: Double, green: Double, blue: Double, size: Int = 8) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    private func centerPixel(of image: CGImage) -> (red: Double, green: Double, blue: Double) {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let center = ((image.height / 2) * image.width + image.width / 2) * 4
        return (Double(pixels[center]) / 255, Double(pixels[center + 1]) / 255, Double(pixels[center + 2]) / 255)
    }

    @Test func originalThemeIsIdentity() {
        let compositor = ThemeCompositor()
        let white = makeImage(red: 1, green: 1, blue: 1)
        let result = compositor.composite(white, theme: BuiltInThemes.original)
        let pixel = centerPixel(of: result)
        #expect(pixel.red > 0.99 && pixel.green > 0.99 && pixel.blue > 0.99)
    }

    @Test func tintOnlyPullsWhiteTowardPaper() {
        let compositor = ThemeCompositor()
        let white = makeImage(red: 1, green: 1, blue: 1)
        let result = compositor.composite(white, theme: BuiltInThemes.sepia)
        let pixel = centerPixel(of: result)
        // Sepia strength 0.6 pulls white toward E8D8B8: red stays highest, blue lowest.
        #expect(pixel.red > pixel.blue)
        #expect(pixel.blue < 0.97)
    }

    @Test func smartInvertDarkensWhite() {
        let compositor = ThemeCompositor()
        let white = makeImage(red: 1, green: 1, blue: 1)
        let result = compositor.composite(white, theme: BuiltInThemes.trueBlack)
        let pixel = centerPixel(of: result)
        // White "paper" should become near the theme's dark background.
        #expect(pixel.red < 0.2 && pixel.green < 0.2 && pixel.blue < 0.2)
    }

    @Test func smartInvertLightensBlackText() {
        let compositor = ThemeCompositor()
        let black = makeImage(red: 0, green: 0, blue: 0)
        let result = compositor.composite(black, theme: BuiltInThemes.trueBlack)
        let pixel = centerPixel(of: result)
        // Black "text" should become light for dark-theme readability.
        #expect(pixel.red > 0.8 && pixel.green > 0.8 && pixel.blue > 0.8)
    }

    @Test func photoHeuristicClassifiesColorfulImage() {
        let compositor = ThemeCompositor()
        let colorful = makeImage(red: 0.8, green: 0.3, blue: 0.2, size: 64)
        #expect(compositor.isPhotoHeavy(colorful))
    }

    @Test func photoHeuristicClassifiesWhitePageAsText() {
        let compositor = ThemeCompositor()
        let white = makeImage(red: 0.98, green: 0.98, blue: 0.97, size: 64)
        #expect(!compositor.isPhotoHeavy(white))
    }
}
