import AppKit
import SwiftUI

/// Render the same vector character used by the desktop window, for the app icon
/// and README previews. This never starts audio capture.
@available(macOS 14.2, *)
public enum ArtworkExport {
    @MainActor public static func write(to directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = CompanionModel()
        defer { model.shutdown() }
        for dancing in [false, true] {
            model.motion = PetMotion(time: 1.1, phase: 1.4, energy: dancing ? 0.65 : 0, bounce: dancing ? 0.65 : 0)
            let renderer = ImageRenderer(content: PetView(model: model))
            renderer.scale = 3
            try save(renderer.nsImage, to: directory.appendingPathComponent(dancing ? "miho-dancing.png" : "miho-idle.png"))
        }
        model.motion = PetMotion(time: 1.1)
        let iconset = directory.appendingPathComponent("Miho.iconset", isDirectory: true)
        try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let content = ZStack {
                    LinearGradient(colors: [Color(red: 0.89, green: 0.94, blue: 0.84),
                                            Color(red: 1, green: 0.93, blue: 0.82)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    PetView(model: model).scaleEffect(2.6)
                }.frame(width: 512, height: 512)
                let renderer = ImageRenderer(content: content)
                renderer.scale = Double(size * scale) / 512
                let suffix = scale == 2 ? "@2x" : ""
                try save(renderer.nsImage, to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }

    private static func save(_ image: NSImage?, to url: URL) throws {
        guard let tiff = image?.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Miho.Artwork", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot render Miho artwork"])
        }
        try data.write(to: url)
    }
}
