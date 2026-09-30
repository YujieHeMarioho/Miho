import AppKit
import SceneKit
import Metal
import MihoCore
import ImageIO
import UniformTypeIdentifiers

/// Render the live 3D rig with the same materials, camera and poses, without audio capture.
@available(macOS 14.2, *)
public enum ArtworkExport {
    @MainActor public static func writeMotion(to url: URL) throws {
        let rig = CharacterScene()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
        renderer.scene = rig.scene; renderer.pointOfView = rig.camera
        // GIF has only one-bit transparency. Opaque preview frames prevent accumulated trails.
        rig.scene.background.contents = NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1)
        let frames = 240
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.gif.identifier as CFString,frames,nil) else {
            throw NSError(domain: "Miho.Artwork",code: 2)
        }
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for index in 0..<frames {
            try autoreleasepool {
                let time = Double(index)/20, moves = DanceMove.allCases
                let step = index/40
                let blend = min(1,Double(index%40)/8)
                let previous = moves[max(0,step-1)], move = moves[step]
                let p = Choreographer.dance(move: previous,phase: time*2,energy: 0.8)
                    .mixed(with: Choreographer.dance(move: move,phase: time*2,energy: 0.8),by: blend*blend*(3-2*blend))
                rig.apply(p,duration: 0)
                let image = renderer.snapshot(atTime: 0,with: CGSize(width: 390,height: 450),antialiasingMode: .multisampling4X)
                guard let cgImage = image.cgImage(forProposedRect: nil,context: nil,hints: nil) else { throw NSError(domain: "Miho.Artwork",code: 3) }
                CGImageDestinationAddImage(destination,cgImage,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.05]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Miho.Artwork",code: 4) }
    }

    @MainActor public static func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let rig = CharacterScene()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
        renderer.scene = rig.scene; renderer.pointOfView = rig.camera
        func render(_ pose: DancePose, size: CGSize = CGSize(width: 780,height: 900)) -> NSImage {
            rig.apply(pose,duration: 0)
            return renderer.snapshot(atTime: 0,with: size,antialiasingMode: .multisampling4X)
        }
        try save(render(DancePose()),to: directory.appendingPathComponent("miho-idle.png"))
        try save(render(Choreographer.dance(move: .armWave,phase: 0.65,energy: 0.8)),to: directory.appendingPathComponent("miho-dancing.png"))
        let tiles = DanceMove.allCases.map { render(Choreographer.dance(move: $0,phase: 0.65,energy: 0.8),size: CGSize(width: 390,height: 450)) }
        let sheet = NSImage(size: NSSize(width: 1_170,height: 1_040),flipped: false) { rect in
            NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1).setFill(); rect.fill()
            for (index,image) in tiles.enumerated() {
                let x = CGFloat(index%3)*390, y = CGFloat(1-index/3)*520
                image.draw(in: NSRect(x: x,y: y+45,width: 390,height: 450))
                let text = NSAttributedString(string: DanceMove.allCases[index].label,attributes: [.font:NSFont.systemFont(ofSize: 21,weight: .semibold),.foregroundColor:NSColor.darkGray])
                text.draw(at: NSPoint(x: x+(390-text.size().width)/2,y: y+20))
            }
            return true
        }
        try save(sheet,to: directory.appendingPathComponent("miho-dance-lineup.png"))
        let iconset = directory.appendingPathComponent("Miho.iconset",isDirectory: true)
        try FileManager.default.createDirectory(at: iconset,withIntermediateDirectories: true)
        let portrait = render(DancePose(),size: CGSize(width: 1_024,height: 1_024))
        for size in [16,32,128,256,512] {
            for scale in [1,2] {
                let dimension = CGFloat(size*scale)
                let icon = NSImage(size: NSSize(width: dimension,height: dimension),flipped: false) { rect in
                    NSGradient(colors: [NSColor(srgbRed: 0.85,green: 0.94,blue: 0.98,alpha: 1),NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1)])?.draw(in: rect,angle: -60)
                    portrait.draw(in: rect.insetBy(dx: -dimension*0.04,dy: -dimension*0.04))
                    return true
                }
                try save(icon,to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
            }
        }
    }
    private static func save(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png,properties: [:]) else {
            throw NSError(domain: "Miho.Artwork",code: 1,userInfo: [NSLocalizedDescriptionKey:"Cannot render Miho artwork"])
        }
        try data.write(to: url)
    }
}
