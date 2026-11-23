import UIKit
@testable import Victoria

/// Small images drawn in code, for tests of the character pipeline and its graders. No
/// image file is checked in, and none of these is anybody's likeness.
enum TestImages {

    /// A PNG of `width` x `height` pixels. `cells` paints flat squares on a grid of
    /// `grid` x `grid` cells: a character is one palette entry, "." is left transparent
    /// (or `background`, when given). With `opaque`, the PNG has no alpha channel at all.
    static func png(width: Int, height: Int, grid: [String] = [], palette: [Character: UIColor] = [:],
                    background: UIColor? = nil, opaque: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            if let background {
                background.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            guard let columns = grid.first?.count, columns > 0 else { return }
            let cellW = CGFloat(width) / CGFloat(columns)
            let cellH = CGFloat(height) / CGFloat(grid.count)
            for (r, row) in grid.enumerated() {
                for (c, ch) in row.enumerated() {
                    guard let color = palette[ch] else { continue }
                    color.setFill()
                    context.fill(CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH, width: cellW, height: cellH))
                }
            }
        }
    }

    static let characterGrid: [String] = [
        "........",
        "..HHHH..",
        ".HSSSSH.",
        ".HESSEH.",
        ".HSMMSH.",
        "..SSSS..",
        ".TTTTTT.",
        "TTTTTTTT",
    ]

    static let characterPalette: [Character: UIColor] = [
        "H": UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1),
        "S": UIColor(red: 0.85, green: 0.65, blue: 0.50, alpha: 1),
        "E": UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
        "M": UIColor(red: 0.60, green: 0.25, blue: 0.25, alpha: 1),
        "T": UIColor(red: 0.20, green: 0.45, blue: 0.70, alpha: 1),
    ]

    /// What a good response holds: a square pixel character on a transparent background
    /// (5 flat colours, about half of the picture transparent, all four corners clear).
    static func characterPNG(side: Int = 64) -> Data {
        png(width: side, height: side, grid: characterGrid, palette: characterPalette)
    }

    /// A stand-in for a photo: an opaque picture with a smooth gradient, so it has far more
    /// colours than pixel art and no transparency.
    static func photo(width: Int, height: Int, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor,
                          UIColor(red: 0.9, green: 0.7, blue: 0.3, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    /// An opaque picture shaded in two directions (red across, green down): what a
    /// photograph or a painted illustration looks like to a colour count, hundreds of colours.
    static func spectrum(side: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let steps = 64
        let cell = CGFloat(side) / CGFloat(steps)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            for y in 0..<steps {
                for x in 0..<steps {
                    UIColor(red: CGFloat(x) / CGFloat(steps - 1), green: CGFloat(y) / CGFloat(steps - 1),
                            blue: 0.5, alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
                }
            }
        }
    }

    /// Pixel width and height of encoded image data.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }
}

/// One part of a `multipart/form-data` body.
struct MultipartPart: Equatable {
    var name: String
    var filename: String?
    var contentType: String?
    var data: Data

    var text: String? { String(data: data, encoding: .utf8) }
}

/// Splits a recorded multipart request back into its parts, reading the boundary from the
/// request's own `Content-Type` header, so a test checks what a server would receive.
enum Multipart {
    static func boundary(of request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Content-Type"),
              header.hasPrefix("multipart/form-data"),
              let range = header.range(of: "boundary=") else { return nil }
        return String(header[range.upperBound...])
    }

    static func parts(of request: URLRequest) -> [MultipartPart] {
        guard let boundary = boundary(of: request), let body = request.httpBody else { return [] }
        let delimiter = Data("--\(boundary)".utf8)
        let headerEnd = Data("\r\n\r\n".utf8)
        var parts: [MultipartPart] = []
        var cursor = body.startIndex
        var sections: [Data] = []
        while let found = body.range(of: delimiter, in: cursor..<body.endIndex) {
            if found.lowerBound > cursor { sections.append(body.subdata(in: cursor..<found.lowerBound)) }
            cursor = found.upperBound
        }
        for section in sections {
            // Each section is "\r\n<headers>\r\n\r\n<content>\r\n".
            guard let split = section.range(of: headerEnd) else { continue }
            let headers = String(decoding: section.subdata(in: section.startIndex..<split.lowerBound), as: UTF8.self)
            var content = section.subdata(in: split.upperBound..<section.endIndex)
            if content.suffix(2) == Data("\r\n".utf8) { content.removeLast(2) }
            func quoted(_ key: String) -> String? {
                guard let start = headers.range(of: "\(key)=\"") else { return nil }
                let rest = headers[start.upperBound...]
                return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
            }
            let contentType = headers.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-type:") }
                .map { $0.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces) }
            guard let name = quoted(" name") else { continue }
            parts.append(MultipartPart(name: name, filename: quoted("filename"), contentType: contentType, data: content))
        }
        return parts
    }
}
