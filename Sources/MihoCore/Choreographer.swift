import Foundation

public enum DanceMood: String, Sendable {
    case dreamy, groovy, lively
    public var label: String { switch self { case .dreamy: return "轻柔陪伴"; case .groovy: return "听着唱腔"; case .lively: return "重音发力" } }
}
/// Describes what the audio is doing; these are not selectable gesture programs.
public enum VocalGesture: String, Sendable {
    case idle, listening, rising, holding, falling, accent, grooving
    public var label: String {
        switch self {
        case .idle: return "安静呼吸"
        case .listening: return "跟随唱句"
        case .rising: return "随唱腔抬起"
        case .holding: return "长音保持"
        case .falling: return "随收句放松"
        case .accent: return "重音发力"
        case .grooving: return "鼓点律动"
        }
    }
}
public struct Rotation3: Equatable, Sendable {
    public var x: Double = 0, y: Double = 0, z: Double = 0
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    func mixed(with b: Self, by t: Double) -> Self { .init(x+(b.x-x)*t,y+(b.y-y)*t,z+(b.z-z)*t) }
}
public struct DancePose: Equatable, Sendable {
    public var x = 0.0, y = 0.0, z = 0.0, squash = 1.0, scale = 1.0
    public var body = Rotation3(), head = Rotation3()
    public var leftEar = Rotation3(), rightEar = Rotation3()
    public var accessoryBounce = 0.0
    public init() {}
    public func mixed(with b: Self, by amount: Double) -> Self {
        let t = amount.isFinite ? min(1,max(0,amount)) : 0
        func mix(_ a: Double, _ b: Double) -> Double { a+(b-a)*t }
        var p = Self()
        p.x = mix(x,b.x); p.y = mix(y,b.y); p.z = mix(z,b.z); p.squash = mix(squash,b.squash); p.scale = mix(scale,b.scale)
        p.body = body.mixed(with: b.body,by: t); p.head = head.mixed(with: b.head,by: t)
        p.leftEar = leftEar.mixed(with: b.leftEar,by: t); p.rightEar = rightEar.mixed(with: b.rightEar,by: t)
        p.accessoryBounce = mix(accessoryBounce,b.accessoryBounce)
        return p
    }
    mutating func add(_ b: Self) {
        x += b.x; y += b.y; z += b.z; squash += b.squash-1; scale += b.scale-1
        body = .init(body.x+b.body.x,body.y+b.body.y,body.z+b.body.z)
        head = .init(head.x+b.head.x,head.y+b.head.y,head.z+b.head.z)
        leftEar = .init(leftEar.x+b.leftEar.x,leftEar.y+b.leftEar.y,leftEar.z+b.leftEar.z)
        rightEar = .init(rightEar.x+b.rightEar.x,rightEar.y+b.rightEar.y,rightEar.z+b.rightEar.z)
        accessoryBounce += b.accessoryBounce
    }
}

/// Two input policies share continuous, speed-limited motion. Singer mode
/// follows articulation and melody; music mode follows drums and learned pulse.
public final class Choreographer {
    public private(set) var mood: DanceMood = .dreamy
    public private(set) var gesture: VocalGesture = .idle
    public private(set) var pose = DancePose()
    public private(set) var impact = 0.0
    public private(set) var vocalDrive = 0.0
    public private(set) var soundDrive = 0.0
    public var intensity = 1.0
    public var mode: DanceMode = .singer {
        didSet {
            guard mode != oldValue else { return }
            resetInput()
            voice = 0; pitchAnchor = nil; pitchOffset = 0; gap = 1
            musicLevel = 0; emphasis = 0; impact = 0; soundDrive = 0
        }
    }
    private var velocity = DancePose()
    private var time = 0.0, gap = 1.0, voice = 0.0, pitchOffset = 0.0
    private var pitchAnchor: Double?, phraseSide = 1.0, phraseIndex = 0
    private var emphasis = 0.0, emphasisTarget = 0.0, releaseAt = -1.0
    private var lastVocal: UInt64 = 0, lastBeat: UInt64 = 0
    private var accentSide = 1.0, lastVocalAt = -10.0, lastDrumAt = -10.0
    private var musicLevel = 0.0, groovePosition = 0.0, grooveInitialized = false, halfTime = false
    private let personality: Double
    public init(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        personality = Double(seed % 1000)/1000 * 2 * .pi
        velocity.squash = 0; velocity.scale = 0
    }
    public func resetInput() {
        lastVocal = 0; lastBeat = 0; lastVocalAt = -10; lastDrumAt = -10; grooveInitialized = false
        // Keep the active phrase across a brief analysis reconnect. A genuine
        // vocal gap releases it through the same path as any other end of phrase.
        emphasisTarget = 0; releaseAt = -1
    }
    @discardableResult public func update(dt rawDT: Double,rhythm r: RhythmFrame,enabled: Bool = true) -> DancePose {
        let dt = rawDT.isFinite ? min(0.1,max(0,rawDT)) : 0
        time += dt
        if mode == .music { return updateMusic(dt: dt,rhythm: r,enabled: enabled) }
        func unit(_ x: Double) -> Double { x.isFinite ? min(1,max(0,x)) : 0 }
        let presence = enabled ? unit(r.vocalPresence) : 0
        let vocalEnergy = enabled ? unit(r.vocalEnergy) : 0
        let voiced = presence > 0.18 && vocalEnergy > 0.025
        let held = unit(r.vocalSustain)*unit(r.vocalConfidence)
        let power = intensity.isFinite ? min(1.5,max(0.5,intensity)) : 1
        if voiced {
            if gap > 0.24 {
                pitchAnchor = nil; pitchOffset = 0
                phraseIndex += 1
                // Once per actual phrase, never on a timer or each drum hit.
                phraseSide = (phraseIndex + Int(personality)) % 2 == 0 ? 1 : -1
            }
            gap = 0
        } else { gap += dt }
        let desiredVoice: Double
        // Loudness owns amplitude even during a long note. Sustain preserves
        // the shape/direction, never an obsolete volume peak.
        if voiced { desiredVoice = vocalEnergy }
        else { desiredVoice = 0 }
        voice += (desiredVoice-voice)*(1-exp(-dt/(desiredVoice > voice ? 0.018 : 0.085)))
        vocalDrive = min(1,pow(max(0,voice)/0.70,1.2))
        if voiced && unit(r.vocalConfidence) > 0.45 && r.vocalPitch.isFinite && (80...900).contains(r.vocalPitch) {
            let pitch = log2(r.vocalPitch)
            if pitchAnchor == nil { pitchAnchor = pitch }
            let relative = min(1,max(-1,(pitch-pitchAnchor!)/0.65))
            pitchOffset += (relative-pitchOffset)*(1-exp(-dt/0.22))
        }
        if gap > 0.24 { pitchOffset *= exp(-dt/0.28) }
        var hit = 0.0
        if r.vocalAccentCount < lastVocal { lastVocal = 0 }
        if r.vocalAccentCount != lastVocal {
            lastVocal = r.vocalAccentCount
            if enabled && r.vocalAccentAge.isFinite && (0..<0.15).contains(r.vocalAccentAge) && time-lastVocalAt > 0.14 {
                // Articulation can add a little punch, but its size remains
                // proportional to this singer's current loudness.
                hit = unit(r.vocalAccentStrength)
                if hit > 0.15 && voiced { accentSide = -accentSide; lastVocalAt = time }
            }
        }
        if hit > 0.025 && voiced {
            emphasisTarget = max(emphasisTarget,hit); releaseAt = time+0.045
        }
        if time > releaseAt || !enabled { emphasisTarget *= exp(-dt/0.16) }
        emphasis += (emphasisTarget-emphasis)*(1-exp(-dt/(emphasisTarget > emphasis ? 0.025 : 0.09)))
        impact = emphasis*power*vocalDrive
        let a = vocalDrive*power
        soundDrive = vocalDrive
        var target = DancePose()
        // No periodic idle motion while audio is active or a phrase is held.
        let idle = 1-min(1,voice*12)
        target.squash = 1+sin(time*1.9+personality)*0.008*idle
        // A held voice holds the same pose. There is no duration-driven
        // extension or programmed syllable cycle; another rise in loudness
        // immediately raises the same continuous target again.
        target.y = a*max(0.04,0.18+pitchOffset*0.16)
        target.x = phraseSide*a*0.04+a*pitchOffset*0.055+accentSide*impact*0.07
        target.z = a*0.025
        target.squash += a*max(0,pitchOffset)*0.012
        target.body.x = a*(0.10-pitchOffset*0.11)
        target.body.y = phraseSide*a*0.18+a*pitchOffset*0.16+accentSide*impact*0.23
        target.body.z = -phraseSide*a*0.04+a*pitchOffset*0.09+accentSide*impact*0.09
        target.head.x = a*(0.05-pitchOffset*0.045)
        target.head.y = -target.body.y*0.36
        target.head.z = -target.body.z*0.40
        target.leftEar.x = -a*0.04; target.rightEar.x = -a*0.035
        // A physical impulse has continuous attack/release, independent of pose.
        target.y += impact*0.045
        target.z += impact*0.04
        target.body.x -= impact*0.09
        target.head.x += impact*0.15
        target.squash -= impact*0.025
        target.accessoryBounce += impact*0.01
        // Grow the complete character, including accessories, on vocal energy.
        // Unlike squash this preserves its round three-dimensional silhouette.
        target.scale = min(1.22,1+a*0.15+impact*0.035)
        target.y = min(0.38,max(0,target.y)); target.x = min(0.2,max(-0.2,target.x))
        mood = impact > 0.20 ? .lively : voice > 0.03 ? .groovy : .dreamy
        if impact > 0.22 && held < 0.5 { gesture = .accent }
        else if !voiced && voice > 0.02 { gesture = .falling }
        else if voice < 0.02 { gesture = .idle }
        else if r.vocalPitchMotion > 0.07 { gesture = .rising }
        else if r.vocalPitchMotion < -0.07 { gesture = .falling }
        else if held > 0.4 { gesture = .holding }
        else { gesture = .listening }
        spring(to: target,dt: dt)
        return pose
    }
    private func updateMusic(dt: Double,rhythm r: RhythmFrame,enabled: Bool) -> DancePose {
        func unit(_ x: Double) -> Double { x.isFinite ? min(1,max(0,x)) : 0 }
        let energy = enabled ? unit(r.energy) : 0
        let bass = enabled ? unit(r.bass) : 0
        let drums = enabled ? unit(r.drumEnergy) : 0
        let desired = max(bass,drums)*0.75+energy*0.25
        musicLevel += (desired-musicLevel)*(1-exp(-dt/(desired > musicLevel ? 0.025 : 0.12)))
        soundDrive = min(1,pow(max(0,musicLevel)/0.65,1.05)); vocalDrive = 0
        let power = intensity.isFinite ? min(1.5,max(0.5,intensity)) : 1
        let bpm = r.pulse.bpm.isFinite ? min(215,max(55,r.pulse.bpm)) : 120
        let support = enabled && r.pulse.bpm > 0 && r.pulse.position.isFinite ? unit(r.pulse.confidence) : 0
        if support > 0.15 {
            if !grooveInitialized { groovePosition = r.pulse.position; grooveInitialized = true }
            else {
                groovePosition += dt*bpm/60
                let error = r.pulse.position-groovePosition
                let wrapped = error-round(error/2)*2
                groovePosition += min(dt*bpm/60*0.65,max(-dt*bpm/60*0.65,wrapped*dt*4))
            }
        } else { grooveInitialized = false }
        if r.beatCount < lastBeat { lastBeat = 0 }
        if r.beatCount != lastBeat {
            lastBeat = r.beatCount
            if enabled && r.beatAge.isFinite && (0..<0.15).contains(r.beatAge) && time-lastDrumAt > 0.18 && unit(r.beatWeight) > 0.3 && energy > 0.005 {
                emphasisTarget = max(emphasisTarget,unit(r.beatStrength)*unit(r.beatWeight))
                releaseAt = time+0.04; lastDrumAt = time
            }
        }
        if time > releaseAt || !enabled { emphasisTarget *= exp(-dt/0.15) }
        emphasis += (emphasisTarget-emphasis)*(1-exp(-dt/(emphasisTarget > emphasis ? 0.025 : 0.09)))
        impact = emphasis*soundDrive*power
        var target = DancePose()
        target.squash = 1+sin(time*1.9+personality)*0.008*(1-min(1,musicLevel*12))
        let g = soundDrive*power*support
        if g > 0.005 {
            if bpm > 160 { halfTime = true } else if bpm < 145 { halfTime = false }
            let omega = 2*Double.pi*bpm/60
            let rate = halfTime ? 0.5 : 1.0
            let bodyOmega = omega*rate
            let bodyPhase = 2*Double.pi*groovePosition*rate+2*atan(bodyOmega/22)
            let nodPhase = 2*Double.pi*groovePosition+2*atan(omega/20)
            let sidePhase = Double.pi*groovePosition+2*atan(omega*0.5/18)
            let bounce = min(0.075,5.5/(bodyOmega*bodyOmega))*g*(1+pow(bodyOmega/22,2))
            target.y = bounce*(1-cos(bodyPhase))
            target.x = 0.09*g*sin(sidePhase)
            target.body.x = min(0.12,8.0/(omega*omega))*g*(1+pow(omega/20,2))*cos(nodPhase)
            target.body.y = 0.20*g*sin(sidePhase)
            target.body.z = -0.09*g*sin(sidePhase)
            target.head.x = 0.07*g*cos(nodPhase)
            target.head.y = -target.body.y*0.3
            target.squash -= 0.015*g*cos(bodyPhase)
        }
        target.y += impact*0.06
        target.body.x += impact*0.10; target.head.x += impact*0.13
        target.squash -= impact*0.022
        target.leftEar.x = impact*0.05; target.rightEar.x = impact*0.04
        target.accessoryBounce = impact*0.008
        target.scale = min(1.18,1+soundDrive*power*0.06+impact*0.025)
        mood = impact > 0.2 ? .lively : soundDrive > 0.05 ? .groovy : .dreamy
        gesture = impact > 0.22 ? .accent : g > 0.02 ? .grooving : soundDrive > 0.02 ? .listening : .idle
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
        step(&pose.scale,&velocity.scale,target.scale,omega: 28,maxSpeed: 1.4,maxAcceleration: 14)
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
