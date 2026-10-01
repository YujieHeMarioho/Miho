import Foundation
import AVFoundation
import MihoCore

/// Developer validation against explicitly supplied files. Does not capture,
/// record, play, or upload system audio. Prints only analysis and pose scalars.
public enum AudioFileProbe {
    public static func run(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat, sampleRate = format.sampleRate
        let analyzer = try SeparatedAudioAnalyzer(sampleRate: sampleRate)
        let engine = Choreographer(seed: 42)
        if CommandLine.arguments.contains("--music-mode") { engine.mode = .music }
        var field = SoundField()
        engine.intensity = 0.8
        let size = AVAudioFrameCount(sampleRate/60)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: size)!
        var time = 0.0, logAt = 0.0, locked = 0.0, elapsed = 0.0
        let start = ProcessInfo.processInfo.systemUptime
        print("t,bpm,confidence,position,probability,y,bodyNod,bodyYaw,vocal,sustain,scale,drive,drums,spectrum,presence")
        while file.framePosition < file.length && time < 90 {
            try file.read(into: buffer,frameCount: size)
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            var stereo = [Float](repeating: 0,count: Int(buffer.frameLength)*2)
            for i in 0..<Int(buffer.frameLength) {
                stereo[i*2] = channels[0][i]
                stereo[i*2+1] = channels[format.channelCount > 1 ? 1 : 0][i]
            }
            let result = analyzer.consume(stereo: stereo,sensitivity: 1)
            if let error = result.error { throw NSError(domain: "Miho.Probe",code: 1,userInfo: [NSLocalizedDescriptionKey:error]) }
            let dt = Double(buffer.frameLength)/sampleRate;time += dt;elapsed += dt
            let r = result.rhythm, p = engine.update(dt: dt,rhythm: r)
            let visual = field.update(rhythm: r,drive: engine.soundDrive,mode: engine.mode)
            if r.pulse.confidence > 0.4 { locked += dt }
            if time >= logAt {
                logAt = time+(CommandLine.arguments.contains("--dense-probe") ? 0 : 0.10)
                print(String(format: "%.3f,%.2f,%.3f,%.4f,%.3f,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f,%.3f,%.3f,%.3f,%.3f",time,r.pulse.bpm,r.pulse.confidence,r.pulse.position,r.pulse.probability+r.pulse.downbeatProbability,p.y,p.body.x,p.body.y,r.vocalEnergy,r.vocalSustain,p.scale,visual.drive,r.drumEnergy,visual.spectrum.max() ?? 0,r.vocalPresence))
            }
        }
        let seconds = ProcessInfo.processInfo.systemUptime-start
        fputs(String(format: "analysis %.2fs for %.2fs audio; pulse supported %.1f%%\n",seconds,elapsed,100*locked/max(elapsed,0.001)),stderr)
    }
}
