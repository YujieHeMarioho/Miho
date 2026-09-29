import Foundation

public enum DanceMood: String, CaseIterable, Sendable {
    case dreamy, groovy, lively
    public var label: String {
        switch self { case .dreamy: return "轻柔陪伴"; case .groovy: return "松弛律动"; case .lively: return "活力满满" }
    }
}

public enum DanceMove: String, CaseIterable, Sendable {
    case twoStep, bodyRoll, armWave, pop, heelToe, happyHop
    public var label: String {
        switch self {
        case .twoStep: return "左右踏步"
        case .bodyRoll: return "身体波浪"
        case .armWave: return "手臂 Wave"
        case .pop: return "定点 Popping"
        case .heelToe: return "脚跟脚尖"
        case .happyHop: return "开心踢步"
        }
    }
}

public struct Rotation3: Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var z: Double = 0
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    func mixed(with b: Self, by t: Double) -> Self { .init(x + (b.x-x)*t, y + (b.y-y)*t, z + (b.z-z)*t) }
}

/// Local joint rotations in radians. The rig owns geometry; the dance engine owns motion.
public struct DancePose: Equatable, Sendable {
    public var x = 0.0, y = 0.0, z = 0.0
    public var squash = 1.0
    public var body = Rotation3(), head = Rotation3()
    public var leftArm = Rotation3(), rightArm = Rotation3()
    public var leftElbow = 0.0, rightElbow = 0.0
    public var leftLeg = Rotation3(), rightLeg = Rotation3()
    public var leftKnee = 0.0, rightKnee = 0.0
    public var leftFoot = Rotation3(), rightFoot = Rotation3()
    public var ear = 0.0, blink = 0.0, smile = 0.0, gaze = 0.0
    public init() {}

    public func mixed(with b: Self, by amount: Double) -> Self {
        let t = min(1, max(0, amount))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b-a)*t }
        var p = Self()
        p.x = mix(x,b.x); p.y = mix(y,b.y); p.z = mix(z,b.z); p.squash = mix(squash,b.squash)
        p.body = body.mixed(with: b.body, by: t); p.head = head.mixed(with: b.head, by: t)
        p.leftArm = leftArm.mixed(with: b.leftArm, by: t); p.rightArm = rightArm.mixed(with: b.rightArm, by: t)
        p.leftElbow = mix(leftElbow,b.leftElbow); p.rightElbow = mix(rightElbow,b.rightElbow)
        p.leftLeg = leftLeg.mixed(with: b.leftLeg, by: t); p.rightLeg = rightLeg.mixed(with: b.rightLeg, by: t)
        p.leftKnee = mix(leftKnee,b.leftKnee); p.rightKnee = mix(rightKnee,b.rightKnee)
        p.leftFoot = leftFoot.mixed(with: b.leftFoot, by: t); p.rightFoot = rightFoot.mixed(with: b.rightFoot, by: t)
        p.ear = mix(ear,b.ear); p.blink = mix(blink,b.blink); p.smile = mix(smile,b.smile); p.gaze = mix(gaze,b.gaze)
        return p
    }
}

/// A continuous groove clock follows plausible onsets, while real beats add short accents.
/// Eight-count phrases blend between coordinated dances. No song metadata is required.
public final class Choreographer {
    public private(set) var mood: DanceMood = .dreamy
    public private(set) var move: DanceMove = .twoStep
    public private(set) var groovePeriod = 0.5
    public private(set) var pose = DancePose()
    private var time = 0.0, phase = 0.0, accent = 0.0, engagement = 0.0
    private var averageEnergy = 0.0, averageBass = 0.0, averageBrightness = 0.0
    private var lastBeatTime = -10.0, lastCount: UInt64 = 0
    private var lastPhrase = -1, phraseSerial = 0
    private var previousMove: DanceMove = .twoStep, transition = 1.0
    private var moodCandidate: DanceMood = .dreamy, moodHold = 0.0
    public init() {}

    @discardableResult public func update(dt rawDT: Double, rhythm: RhythmFrame, enabled: Bool = true) -> DancePose {
        let dt = rawDT.isFinite ? min(0.1, max(0, rawDT)) : 0
        time += dt
        func safe(_ value: Double) -> Double { value.isFinite ? min(1,max(0,value)) : 0 }
        let energy = enabled ? safe(rhythm.energy) : 0
        let smoothing = 1 - exp(-dt / 0.65)
        averageEnergy += (energy-averageEnergy)*smoothing
        averageBass += (safe(rhythm.bassShare)-averageBass)*smoothing
        averageBrightness += (safe(rhythm.brightness)-averageBrightness)*smoothing
        let targetMood: DanceMood = averageEnergy > 0.52 || (averageEnergy > 0.30 && averageBrightness > 0.45) ? .lively : averageEnergy > 0.12 ? .groovy : .dreamy
        if targetMood == moodCandidate { moodHold += dt } else { moodCandidate = targetMood; moodHold = 0 }
        if moodHold > 1.2 { mood = moodCandidate }

        if rhythm.beatCount < lastCount { lastBeatTime = -10; lastCount = rhythm.beatCount }
        if enabled && rhythm.beatCount > lastCount {
            let interval = time-lastBeatTime
            if (0.28...0.9).contains(interval) { groovePeriod += (interval-groovePeriod)*0.25 }
            lastBeatTime = time; lastCount = rhythm.beatCount; accent = 1
        }
        accent *= exp(-dt/0.10)
        // A small rate correction preserves position continuity instead of resetting on every onset.
        let elapsed = time-lastBeatTime
        let error = elapsed < 1 ? sin((elapsed/groovePeriod-phase)*2 * .pi) : 0
        phase += dt / groovePeriod + error*dt*0.65
        let targetEngagement = energy > 0.012 ? min(1, 0.25 + energy*1.3) : 0
        engagement += (targetEngagement-engagement)*(1-exp(-dt/(targetEngagement > engagement ? 0.10 : 0.18)))
        let phrase = Int(phase/8)
        if phrase != lastPhrase && engagement > 0.15 {
            lastPhrase = phrase
            let sequence: [DanceMove]
            switch mood {
            case .dreamy: sequence = [.twoStep, .bodyRoll, .armWave]
            case .groovy: sequence = averageBass > 0.35 ? [.twoStep, .pop, .heelToe, .bodyRoll, .armWave] : [.twoStep, .bodyRoll, .armWave, .heelToe, .pop]
            case .lively: sequence = [.pop, .happyHop, .heelToe, .armWave, .twoStep, .bodyRoll]
            }
            var next = sequence[phraseSerial % sequence.count]
            if next == move && phraseSerial > 0 { next = sequence[(phraseSerial+1) % sequence.count] }
            previousMove = move; move = next; transition = 0; phraseSerial += 1
        }
        transition = min(1, transition+dt/0.38)
        let ease = transition*transition*(3-2*transition)
        let danced = Self.dance(move: previousMove, phase: phase, energy: energy, accent: accent)
            .mixed(with: Self.dance(move: move, phase: phase, energy: energy, accent: accent), by: ease)
        var idle = DancePose()
        idle.squash = 1 + sin(time*2.1)*0.012
        idle.head = Rotation3(sin(time*0.8)*0.025, sin(time*0.45)*0.09, sin(time*0.7)*0.035)
        idle.leftArm.z = -0.10; idle.rightArm.z = 0.10
        idle.ear = sin(time*1.5)*0.025
        idle.smile = 0.12
        idle.gaze = sin(time*0.45)*0.018
        pose = idle.mixed(with: danced, by: engagement)
        let blinkTime = time.truncatingRemainder(dividingBy: 4.7)
        pose.blink = blinkTime > 4.45 ? pow(sin((blinkTime-4.45)/0.25 * .pi),2) : 0
        return pose
    }

    /// Also used by the artwork exporter: previews and the live rig share exactly the same poses.
    public static func dance(move: DanceMove, phase: Double, energy: Double, accent: Double = 0) -> DancePose {
        let a = min(1,max(0,energy)), b = phase*2 * .pi
        let s = sin(b/2), c = cos(b/2), pulse = (1-cos(b))/2
        var p = DancePose()
        p.y = 0.03 + pulse*0.045 + accent*0.025
        p.body = Rotation3(0.04+pulse*0.07, s*0.10, s*0.05)
        p.head = Rotation3(-pulse*0.10, -s*0.13, -s*0.04)
        p.leftArm = Rotation3(-0.1,0,-0.18); p.rightArm = Rotation3(-0.1,0,0.18)
        p.leftElbow = -0.18; p.rightElbow = -0.18
        p.leftKnee = pulse*0.12; p.rightKnee = pulse*0.12
        p.ear = sin(b/2-0.8)*0.10 + accent*0.08
        p.smile = 0.3 + a*0.6
        switch move {
        case .twoStep:
            p.x = s*0.14; p.body.z = -s*0.10; p.body.y = s*0.18
            p.leftLeg = Rotation3(0,0,-max(0,s)*0.24); p.rightLeg = Rotation3(0,0,-min(0,s)*0.24)
            p.leftKnee += max(0,c)*0.22; p.rightKnee += max(0,-c)*0.22
            p.leftArm.x = c*0.35; p.rightArm.x = -c*0.35
            p.leftElbow = -0.35-max(0,-c)*0.4; p.rightElbow = -0.35-max(0,c)*0.4
        case .bodyRoll:
            p.body = Rotation3(sin(b/2)*0.22, cos(b/2)*0.2, sin(b/2+1)*0.12)
            p.head = Rotation3(-sin(b/2-0.8)*0.18,-cos(b/2)*0.1, -sin(b/2+0.3)*0.13)
            p.x = sin(b/2+0.6)*0.09; p.z = cos(b/2)*0.05
            p.leftArm.z = -0.45-sin(b/2)*0.18; p.rightArm.z = 0.45-sin(b/2)*0.18
            p.leftElbow = -0.65; p.rightElbow = -0.65
        case .armWave:
            p.body.z = s*0.12; p.head.z = -s*0.16
            p.leftArm = Rotation3(-0.20,0,-1.0-sin(b/2)*0.45)
            p.rightArm = Rotation3(-0.20,0,1.0+sin(b/2-1.4)*0.45)
            p.leftElbow = -0.55-sin(b/2-0.8)*0.45; p.rightElbow = -0.55-sin(b/2-2.2)*0.45
            p.leftKnee += max(0,s)*0.18; p.rightKnee += max(0,-s)*0.18
        case .pop:
            let hit = pow(max(0,cos(b)),8)
            p.body.x = -hit*0.14; p.body.y = s*0.28; p.head.x = hit*0.20
            p.squash = 1-hit*0.035
            p.leftArm = Rotation3(-0.50-hit*0.35,0,-0.45)
            p.rightArm = Rotation3(-0.50-hit*0.35,0,0.45)
            p.leftElbow = -0.65+hit*0.40; p.rightElbow = -0.65+hit*0.40
            p.leftFoot.y = s*0.20; p.rightFoot.y = s*0.20
        case .heelToe:
            p.x = s*0.13; p.body.y = -s*0.22; p.head.y = s*0.22
            p.leftLeg.y = sin(b/2)*0.32; p.rightLeg.y = -sin(b/2)*0.32
            p.leftFoot = Rotation3(max(0,c)*0.24,s*0.35,0)
            p.rightFoot = Rotation3(max(0,-c)*0.24,-s*0.35,0)
            p.leftArm.z = -0.45-c*0.18; p.rightArm.z = 0.45-c*0.18
            p.leftElbow = -0.40; p.rightElbow = -0.40
        case .happyHop:
            let left = max(0,s), right = max(0,-s)
            p.y = 0.05+pulse*(0.09+a*0.06); p.x = s*0.10
            p.leftLeg.x = -left*0.65; p.rightLeg.x = -right*0.65
            p.leftKnee = left*0.55; p.rightKnee = right*0.55
            p.leftArm = Rotation3(-0.3,0,-0.7-left*0.7); p.rightArm = Rotation3(-0.3,0,0.7+right*0.7)
            p.leftElbow = -0.3; p.rightElbow = -0.3
            p.body.z = -s*0.12; p.head.z = s*0.12
        }
        return p
    }
}
