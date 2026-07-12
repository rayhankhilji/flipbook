import AppKit

extension NSImage {
    /// Best-effort conversion to `CGImage` for handing rendered thumbnails to Core Image/Core Graphics code.
    func cgImageForProxy() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
