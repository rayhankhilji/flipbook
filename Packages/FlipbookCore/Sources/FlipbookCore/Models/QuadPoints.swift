import CoreGraphics
import Foundation

/// Serializes highlight geometry (rects in PDF page space, bottom-left origin) to the
/// `Data` blob stored on `Highlight.quadPointsData`. JSON of [x, y, w, h] arrays —
/// human-inspectable and stable across app versions.
public enum QuadPoints {
    public static func encode(_ rects: [CGRect]) -> Data {
        let arrays = rects.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] }
        return (try? JSONEncoder().encode(arrays)) ?? Data()
    }

    public static func decode(_ data: Data) -> [CGRect] {
        guard let arrays = try? JSONDecoder().decode([[CGFloat]].self, from: data) else { return [] }
        return arrays.compactMap { values in
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
    }
}
