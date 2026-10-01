import AppKit
import SceneKit
import Metal
import MihoCore
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

/// Render the live 3D rig with the same materials, camera and poses, without audio capture.
@available(macOS 14.2, *)
public enum ArtworkExport {
    @MainActor public static func writeMotion(to url: URL) throws {
        try writeVocalMotion(to: url)
    }
    @MainActor public static func writeVocalMotion(to url: URL) throws {
        let rig = CharacterScene()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
        renderer.scene = rig.scene; renderer.pointOfView = rig.camera
        // GIF has only one-bit transparency. Opaque preview frames prevent accumulated trails.
        rig.scene.background.contents = NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1)
        let frames = 300
        let engine = Choreographer(seed: 42)
        if CommandLine.arguments.contains("--music-mode") { engine.mode = .music }
        let beatClock = engine.mode == .music ? try LearnedBeatAnalyzer() : nil
        let analyzer = RhythmAnalyzer()
        let drums = RhythmAnalyzer(analyzeVoice: false)
        let mixture = RhythmAnalyzer(analyzeVoice: false)
        var field = SoundField()
        var rhythm = RhythmFrame(), sample = 0, vocalPhase = 0.0
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.gif.identifier as CFString,frames,nil) else {
            throw NSError(domain: "Miho.Artwork",code: 2)
        }
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frameIndex in 0..<frames {
            try autoreleasepool {
                // Feed the real analyzer: two short voiced syllables, a held
                // melodic rise/fall, kicks/snares and light hats per phrase.
                for _ in 0..<2 {
                    for _ in 0..<800 {
                        let time = Double(sample)/48_000, phrase = time.truncatingRemainder(dividingBy: 10)
                        var envelope = 0.0
                        for start in [0.15,0.65] {
                            let age = phrase-start
                            if age >= 0 && age < 0.25 { envelope += (start < 0.5 ? 0.05 : 0.25)*min(1,age/0.015)*min(1,(0.25-age)/0.04) }
                        }
                        if (1.05...8.0).contains(phrase) {
                            let loudness = phrase < 3 ? 0.05 : phrase < 5.2 ? 0.24 : 0.055
                            envelope += loudness*min(1,(phrase-1.05)/0.12)*min(1,(8.0-phrase)/0.30)
                        }
                        let frequency = 220*pow(2,0.45*min(1,max(0,(phrase-1.05)/3)))
                        vocalPhase += 2 * .pi*frequency/48_000
                        let value = envelope*(sin(vocalPhase)+0.4*sin(2*vocalPhase)+0.18*sin(3*vocalPhase))
                        var percussion = 0.0
                        let drumAge = time.truncatingRemainder(dividingBy: 0.5)
                        if drumAge < 0.10 {
                            if Int(time/0.5)%2 == 0 { percussion += 0.22*sin(2 * .pi*60*drumAge)*exp(-drumAge/0.035) }
                            else { percussion += 0.09*(sin(2 * .pi*2_300*drumAge)+sin(2 * .pi*6_400*drumAge))*exp(-drumAge/0.018) }
                        }
                        let hatAge = time.truncatingRemainder(dividingBy: 0.125)
                        percussion += 0.025*sin(2 * .pi*8_000*hatAge)*exp(-hatAge/0.008)
                        rhythm = analyzer.consume(Float(value))
                        let beat = drums.consume(Float(percussion))
                        let combined = mixture.consume(Float(value+percussion))
                        rhythm.vocalSpectrum = rhythm.spectrum
                        rhythm.drumSpectrum = beat.spectrum
                        rhythm.spectrum = combined.spectrum
                        if let beatClock { rhythm.pulse = try beatClock.consume(Float(value+percussion)) }
                        rhythm.energy = combined.energy
                        rhythm.bass = combined.bass; rhythm.mid = combined.mid; rhythm.treble = combined.treble
                        rhythm.drumEnergy = beat.energy
                        rhythm.beatCount = beat.beatCount; rhythm.beatAge = beat.beatAge
                        rhythm.beatStrength = beat.beatStrength; rhythm.beatWeight = beat.beatWeight
                        sample += 1
                    }
                    engine.update(dt: 1/60,rhythm: rhythm)
                    field.update(rhythm: rhythm,drive: engine.soundDrive,mode: engine.mode)
                }
                rig.setSoundField(field.frame)
                rig.apply(engine.pose,duration: 0)
                renderer.scene?.background.contents = CommandLine.arguments.contains("--light-preview")
                    ? NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1)
                    : NSColor(srgbRed: 0.035,green: 0.06,blue: 0.15,alpha: 1)
                let size = CGSize(width: 390,height: 450)
                let character = renderer.snapshot(atTime: 0,with: size,antialiasingMode: .multisampling4X)
                let image = character
                if frameIndex == 145 {
                    try save(image,to: url.deletingPathExtension().appendingPathExtension("png"))
                }
                guard let cgImage = image.cgImage(forProposedRect: nil,context: nil,hints: nil) else { throw NSError(domain: "Miho.Artwork",code: 3) }
                CGImageDestinationAddImage(destination,cgImage,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/30]] as CFDictionary)
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
        let engine = Choreographer(seed: 42)
        var cue = RhythmFrame(); cue.energy = 0.8; cue.vocalEnergy = 0.8
        cue.vocalPresence = 0.9; cue.vocalConfidence = 0.9; cue.vocalPitch = 220; cue.vocalSustain = 0.9
        var tiles: [NSImage] = []
        for stage in 0..<4 {
            for _ in 0..<60 {
                cue.vocalPitch = 220*pow(2,Double(stage)*0.2)
                if stage == 3 { cue.vocalPresence = 0; cue.vocalEnergy = 0 }
                engine.update(dt: 1/60,rhythm: cue)
            }
            tiles.append(render(engine.pose,size: CGSize(width: 390,height: 450)))
        }
        try save(tiles[2],to: directory.appendingPathComponent("miho-dancing.png"))
        let labels = ["起句","唱腔上扬","长音保持","收句放松"]
        let sheet = NSImage(size: NSSize(width: 780,height: 1_040),flipped: false) { rect in
            NSColor(srgbRed: 0.97,green: 0.98,blue: 0.99,alpha: 1).setFill(); rect.fill()
            for (index,image) in tiles.enumerated() {
                let x = CGFloat(index%2)*390, y = CGFloat(1-index/2)*520
                image.draw(in: NSRect(x: x,y: y+45,width: 390,height: 450))
                let text = NSAttributedString(string: labels[index],attributes: [.font:NSFont.systemFont(ofSize: 21,weight: .semibold),.foregroundColor:NSColor.darkGray])
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
