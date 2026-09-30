import Foundation

public enum DanceMood: String, Sendable {
    case dreamy, groovy, lively
    public var label: String { switch self { case .dreamy: return "轻柔陪伴"; case .groovy: return "听着唱腔"; case .lively: return "重音发力" } }
}
/// Describes what the audio is doing; these are not selectable gesture programs.
public enum VocalGesture: String, Sendable {
    case idle, listening, rising, holding, falling, accent
    public var label: String {
        switch self {
        case .idle: return "安静呼吸"
        case .listening: return "跟随唱句"
        case .rising: return "随唱腔抬起"
        case .holding: return "长音保持"
        case .falling: return "随收句放松"
        case .accent: return "重音发力"
        }
    }
}
public struct Rotation3: Equatable, Sendable {
    public var x: Double = 0, y: Double = 0, z: Double = 0
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    func mixed(with b: Self, by t: Double) -> Self { .init(x+(b.x-x)*t,y+(b.y-y)*t,z+(b.z-z)*t) }
}
public struct DancePose: Equatable, Sendable {
    public var x = 0.0, y = 0.0, z = 0.0, squash = 1.0
    public var body = Rotation3(), head = Rotation3()
    public var leftEar = Rotation3(), rightEar = Rotation3()
    public var accessoryBounce = 0.0
    public init() {}
    public func mixed(with b: Self, by amount: Double) -> Self {
        let t = amount.isFinite ? min(1,max(0,amount)) : 0
        func mix(_ a: Double, _ b: Double) -> Double { a+(b-a)*t }
        var p = Self()
        p.x = mix(x,b.x); p.y = mix(y,b.y); p.z = mix(z,b.z); p.squash = mix(squash,b.squash)
        p.body = body.mixed(with: b.body,by: t); p.head = head.mixed(with: b.head,by: t)
        p.leftEar = leftEar.mixed(with: b.leftEar,by: t); p.rightEar = rightEar.mixed(with: b.rightEar,by: t)
        p.accessoryBounce = mix(accessoryBounce,b.accessoryBounce)
        return p
    }
    mutating func add(_ b: Self) {
        x += b.x; y += b.y; z += b.z; squash += b.squash-1
        body = .init(body.x+b.body.x,body.y+b.body.y,body.z+b.body.z)
        head = .init(head.x+b.head.x,head.y+b.head.y,head.z+b.head.z)
        leftEar = .init(leftEar.x+b.leftEar.x,leftEar.y+b.leftEar.y,leftEar.z+b.leftEar.z)
        rightEar = .init(rightEar.x+b.rightEar.x,rightEar.y+b.rightEar.y,rightEar.z+b.rightEar.z)
        accessoryBounce += b.accessoryBounce
    }
}

/// Continuous audio-to-pose mapping. No dance clips, beat oscillator or timed
/// left/right loop. A vocal phrase keeps its pitch anchor and orientation until
/// the singer releases it. Accents settle back into that current posture.
public final class Choreographer {
    public private(set) var mood: DanceMood = .dreamy
    public private(set) var gesture: VocalGesture = .idle
    public private(set) var pose = DancePose()
    public private(set) var impact = 0.0
    public var intensity = 1.0
    private var velocity = DancePose()
    private var time = 0.0, phraseAge = 0.0, gap = 1.0, voice = 0.0, pitchOffset = 0.0, phrasePeak = 0.0
    private var pitchAnchor: Double?, phraseSide = 1.0, phraseIndex = 0
    private var emphasis = 0.0, emphasisTarget = 0.0, releaseAt = -1.0, lastHit = -10.0
    private var lastBeat: UInt64 = 0, lastVocal: UInt64 = 0
    private let personality: Double
    public init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        personality = Double(seed % 1000)/1000 * 2 * .pi
        velocity.squash = 0
    }
    public func resetInput() {
        lastBeat = 0; lastVocal = 0
        // Keep the active phrase across a brief analysis reconnect. A genuine
        // vocal gap releases it through the same path as any other end of phrase.
        emphasisTarget = 0; releaseAt = -1; lastHit = -10
    }
    @discardableResult public func update(dt rawDT: Double,rhythm r: RhythmFrame,enabled: Bool = true) -> DancePose {
        let dt = rawDT.isFinite ? min(0.1,max(0,rawDT)) : 0
        time += dt
        func unit(_ x: Double) -> Double { x.isFinite ? min(1,max(0,x)) : 0 }
        let energy = enabled ? unit(r.energy) : 0
        let presence = enabled ? unit(r.vocalPresence) : 0
        let vocalEnergy = enabled ? unit(r.vocalEnergy) : 0
        let voiced = presence > 0.22 && vocalEnergy > 0.035
        let power = intensity.isFinite ? min(1.5,max(0.5,intensity)) : 1
        if voiced {
            if gap > 0.24 {
                phraseAge = 0; pitchAnchor = nil; pitchOffset = 0; phrasePeak = 0
                phraseIndex += 1
                // Once per actual phrase, never on a timer or each drum hit.
                phraseSide = (phraseIndex + Int(personality)) % 2 == 0 ? 1 : -1
            }
            gap = 0; phraseAge += dt; phrasePeak = max(phrasePeak,vocalEnergy)
        } else { gap += dt }
        let desiredVoice = voiced || gap < 0.18 ? max(vocalEnergy,phrasePeak*0.80) : 0
        voice += (desiredVoice-voice)*(1-exp(-dt/(desiredVoice > voice ? 0.07 : 0.24)))
        if voiced && unit(r.vocalConfidence) > 0.45 && r.vocalPitch.isFinite && (80...900).contains(r.vocalPitch) {
            let pitch = log2(r.vocalPitch)
            if pitchAnchor == nil { pitchAnchor = pitch }
            let relative = min(1,max(-1,(pitch-pitchAnchor!)/0.65))
            pitchOffset += (relative-pitchOffset)*(1-exp(-dt/0.22))
        }
        if gap > 0.24 { pitchOffset *= exp(-dt/0.28) }
        let extensionAmount = 1-exp(-max(0,phraseAge-0.12)/0.8)
        let held = max(unit(r.vocalSustain),voiced ? extensionAmount*0.85 : 0)
        var hit = 0.0
        if r.beatCount < lastBeat { lastBeat = 0 }
        if r.beatCount != lastBeat {
            lastBeat = r.beatCount
            if enabled && r.beatAge.isFinite && r.beatAge < 0.15 && r.beatAge >= 0 && time-r.beatAge-lastHit > 0.22 {
                // Separated drums: weak subdivisions do not shake a held vocal.
                hit = unit(r.beatStrength)*unit(r.beatWeight)*(1-held*0.85)*(1-min(1,voice)*0.45)
            }
        }
        if r.vocalAccentCount < lastVocal { lastVocal = 0 }
        if r.vocalAccentCount != lastVocal {
            lastVocal = r.vocalAccentCount
            if enabled && r.vocalAccentAge.isFinite && (0..<0.15).contains(r.vocalAccentAge) {
                hit = max(hit,unit(r.vocalAccentStrength))
            }
        }
        if hit > 0.18 && energy > 0.005 {
            emphasisTarget = max(emphasisTarget,hit); releaseAt = time+0.045; lastHit = time
        }
        if time > releaseAt || !enabled { emphasisTarget *= exp(-dt/0.16) }
        emphasis += (emphasisTarget-emphasis)*(1-exp(-dt/(emphasisTarget > emphasis ? 0.025 : 0.09)))
        impact = emphasis*power
        let a = voice*power
        var target = DancePose()
        // No periodic idle motion while audio is active or a phrase is held.
        let idle = 1-min(1,max(energy,voice)*12)
        target.squash = 1+sin(time*1.9+personality)*0.008*idle
        target.body.y = sin(time*0.43+personality)*0.025*idle
        target.y = a*max(0,0.045+extensionAmount*0.20+pitchOffset*0.16)
        target.x = phraseSide*a*(0.025+extensionAmount*0.045)
        target.z = a*0.035
        target.squash += a*(0.012+max(0,pitchOffset)*0.018)
        target.body.x = -a*(extensionAmount*0.07+pitchOffset*0.11)
        target.body.y += phraseSide*a*(0.08+extensionAmount*0.22)
        target.body.z = -phraseSide*a*(0.025+extensionAmount*0.06)
        target.head.x = -a*(extensionAmount*0.035+pitchOffset*0.045)
        target.head.y = -target.body.y*0.18
        target.leftEar.x = -a*extensionAmount*0.06; target.rightEar.x = -a*extensionAmount*0.05
        // A physical impulse has continuous attack/release, independent of pose.
        target.y += impact*0.045
        target.z += impact*0.07
        target.body.x -= impact*0.09
        target.head.x += impact*0.15
        target.squash -= impact*0.025
        target.accessoryBounce = impact*0.01
        target.y = min(0.38,max(0,target.y)); target.x = min(0.2,max(-0.2,target.x))
        mood = impact > 0.20 ? .lively : voice > 0.03 ? .groovy : .dreamy
        if impact > 0.22 && held < 0.5 { gesture = .accent }
        else if !voiced && voice > 0.02 { gesture = .falling }
        else if voice < 0.02 { gesture = .idle }
        else if r.vocalPitchMotion > 0.07 { gesture = .rising }
        else if r.vocalPitchMotion < -0.07 { gesture = .falling }
        else if held > 0.4 || phraseAge > 0.8 { gesture = .holding }
        else { gesture = .listening }
        spring(to: target,dt: dt)
        return pose
    }
    private func spring(to target: DancePose,dt: Double) {
        guard dt > 0 else { return }
        func step(_ value: inout Double,_ speed: inout Double,_ goal: Double,
                  omega: Double = 22,maxSpeed: Double = 1.2,maxAcceleration: Double = 8) {
            let displacement = value-goal, c = speed+omega*displacement
            let decay = exp(-omega*dt)
            let nextSpeed = (speed-omega*c*dt)*decay
            let limited = min(maxSpeed,max(-maxSpeed,speed+min(maxAcceleration*dt,max(-maxAcceleration*dt,nextSpeed-speed))))
            value += (speed+limited)*0.5*dt
            speed = limited
        }
        step(&pose.x,&velocity.x,target.x)
        step(&pose.y,&velocity.y,target.y,maxSpeed: 0.9)
        step(&pose.z,&velocity.z,target.z)
        step(&pose.squash,&velocity.squash,target.squash,omega: 26,maxSpeed: 0.45,maxAcceleration: 4)
        step(&pose.body.x,&velocity.body.x,target.body.x,omega: 20,maxSpeed: 2,maxAcceleration: 12)
        step(&pose.body.y,&velocity.body.y,target.body.y,omega: 18,maxSpeed: 2.8,maxAcceleration: 14)
        step(&pose.body.z,&velocity.body.z,target.body.z,omega: 20,maxSpeed: 2,maxAcceleration: 12)
        step(&pose.head.x,&velocity.head.x,target.head.x,omega: 24,maxSpeed: 2,maxAcceleration: 14)
        step(&pose.head.y,&velocity.head.y,target.head.y,omega: 20,maxSpeed: 2,maxAcceleration: 12)
        step(&pose.head.z,&velocity.head.z,target.head.z,omega: 20,maxSpeed: 2,maxAcceleration: 12)
        step(&pose.leftEar.x,&velocity.leftEar.x,target.leftEar.x,omega: 18,maxSpeed: 3,maxAcceleration: 18)
        step(&pose.rightEar.x,&velocity.rightEar.x,target.rightEar.x,omega: 18,maxSpeed: 3,maxAcceleration: 18)
        step(&pose.leftEar.y,&velocity.leftEar.y,target.leftEar.y)
        step(&pose.rightEar.y,&velocity.rightEar.y,target.rightEar.y)
        step(&pose.leftEar.z,&velocity.leftEar.z,target.leftEar.z)
        step(&pose.rightEar.z,&velocity.rightEar.z,target.rightEar.z)
        step(&pose.accessoryBounce,&velocity.accessoryBounce,target.accessoryBounce,omega: 18,maxSpeed: 0.25,maxAcceleration: 3)
    }
}
