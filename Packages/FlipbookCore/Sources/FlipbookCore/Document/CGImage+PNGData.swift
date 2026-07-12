import AppKit
import CoreGraphics

extension CGImage {
    /// Encodes to PNG data for storing in `Book.coverImageData` (`.externalStorage`).
    func pngData() -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: self)
        return bitmap.representation(using: .png, properties: [:])
    }
}
