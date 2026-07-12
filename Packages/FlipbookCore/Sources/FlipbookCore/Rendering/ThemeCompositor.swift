import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Applies a theme's color treatment to rasterized PDF page pixels, e-reader style.
/// Runs once per cached page image (inside `PageRenderer`), never per frame.
///
/// One shared instance holds a single GPU-backed `CIContext` — `CIContext` is immutable
/// and thread-safe, and creating one per page render is a well-known perf mistake.
public final class ThemeCompositor: Sendable {
    public static let shared = ThemeCompositor()

    private let context: CIContext

    public init() {
        // Work in gamma-encoded sRGB, not Core Image's default linear space: the theme
        // matrix coefficients are authored against sRGB pixel values, and linear-space
        // inversion would render dark themes noticeably lighter than designed.
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        self.context = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: srgb as Any,
        ])
    }

    /// The hook shape `PageRenderer` expects. Accepts plain theme IDs or full render
    /// keys carrying the user's warmth/brightness adjustments (`ThemeRenderKey`).
    public func makeRendererHook() -> @Sendable (CGImage, String) -> CGImage {
        { [self] image, themeKey in
            composite(image, theme: ThemeRenderKey.resolve(themeKey))
        }
    }

    public func composite(_ image: CGImage, theme: ThemeDefinition) -> CGImage {
        let parameters = theme.filterParameters
        guard parameters.strength > 0 || parameters.warmth != 0 || parameters.brightness != 0 else {
            return image
        }

        let input = CIImage(cgImage: image)
        var output: CIImage
        switch theme.pdfContentStrategy {
        case .tintOnly:
            output = paperTint(input, theme: theme)
        case .smartInvert:
            output = smartInvert(input, theme: theme)
        case .imageAwareInvert:
            // Photo/scan-heavy pages get dimmed rather than inverted so images
            // aren't color-negated; text pages get the full smart invert.
            output = isPhotoHeavy(image)
                ? dimOnly(input, theme: theme)
                : smartInvert(input, theme: theme)
        }
        output = warmthAndBrightness(output, parameters: theme.filterParameters)

        guard let result = context.createCGImage(output, from: input.extent) else {
            return image
        }
        return result
    }

    // MARK: - Strategies

    /// Multiplies white toward the theme's paper color: out = mix(1, paper, strength) · in.
    /// Safe for all content including photos — never inverts anything.
    private func paperTint(_ input: CIImage, theme: ThemeDefinition) -> CIImage {
        let paper = theme.pageBackground
        let s = theme.filterParameters.strength
        return colorMatrix(
            input,
            scale: (
                mix(1, paper.red, s),
                mix(1, paper.green, s),
                mix(1, paper.blue, s)
            ),
            bias: (0, 0, 0)
        )
    }

    /// Classic lightness-preserving invert: invert then rotate hue 180° so colors keep
    /// their identity (blue stays blue), then remap black to the theme's page background
    /// so "paper" becomes the theme's dark tone rather than pure black.
    private func smartInvert(_ input: CIImage, theme: ThemeDefinition) -> CIImage {
        var image = colorMatrix(input, scale: (-1, -1, -1), bias: (1, 1, 1))

        let hue = CIFilter.hueAdjust()
        hue.inputImage = image
        hue.angle = .pi
        image = hue.outputImage ?? image

        let bg = theme.pageBackground
        return colorMatrix(
            image,
            scale: (1 - bg.red, 1 - bg.green, 1 - bg.blue),
            bias: (bg.red, bg.green, bg.blue)
        )
    }

    /// Fallback for photo-heavy pages under dark themes: keep the image positive,
    /// just pull its brightness down so it doesn't blind against a dark canvas.
    private func dimOnly(_ input: CIImage, theme: ThemeDefinition) -> CIImage {
        let s = theme.filterParameters.strength
        let dim = mix(1, 0.68, s)
        return colorMatrix(input, scale: (dim, dim, dim), bias: (0, 0, 0))
    }

    private func warmthAndBrightness(_ input: CIImage, parameters: PDFFilterParameters) -> CIImage {
        var image = input

        if parameters.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = image
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 6500 - parameters.warmth * 2000, y: 0)
            image = temperature.outputImage ?? image
        }

        if parameters.brightness != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = image
            exposure.ev = Float(parameters.brightness * 2)
            image = exposure.outputImage ?? image
        }

        return image
    }

    // MARK: - Photo-heavy heuristic

    /// Cheap classification of a rendered page as photo/scan-heavy vs. text-on-white,
    /// via a 48×48 downsample: text pages stay dominated by near-white pixels (margins,
    /// line spacing) and have little color; photo pages are colorful and/or lose most
    /// of their white area. Grayscale photo scans can misclassify — a documented v1
    /// limitation surfaced in the theme picker help text.
    func isPhotoHeavy(_ image: CGImage) -> Bool {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let sampler = CGContext(
                  data: &pixels,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: side * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }

        sampler.interpolationQuality = .low
        sampler.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var colorfulCount = 0
        var nearWhiteCount = 0
        let total = side * side

        for index in 0..<total {
            let offset = index * 4
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255

            let maxChannel = max(red, green, blue)
            let saturation = maxChannel > 0 ? (maxChannel - min(red, green, blue)) / maxChannel : 0

            if saturation > 0.18 && maxChannel > 0.15 {
                colorfulCount += 1
            }
            if maxChannel > 0.85 && saturation < 0.1 {
                nearWhiteCount += 1
            }
        }

        let colorfulFraction = Double(colorfulCount) / Double(total)
        let whiteFraction = Double(nearWhiteCount) / Double(total)
        return colorfulFraction > 0.12 || whiteFraction < 0.35
    }

    // MARK: - Helpers

    private func colorMatrix(
        _ input: CIImage,
        scale: (Double, Double, Double),
        bias: (Double, Double, Double)
    ) -> CIImage {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = input
        filter.rVector = CIVector(x: scale.0, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: scale.1, z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: scale.2, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filter.biasVector = CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
        return filter.outputImage ?? input
    }

    private func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
