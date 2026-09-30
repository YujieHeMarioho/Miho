import Foundation

/// Mouse rotation is separate from dance motion and window position. The gesture follows
/// the pointer immediately; release carries a little momentum, with an optional spring to the front.
public final class DragRotation {
    public private(set) var rotation = Rotation3()
    public private(set) var isDragging = false
    public var automaticallyReturns = true
    private var yawVelocity = 0.0, pitchVelocity = 0.0, releaseAge = 0.0
    public init() {}

    public func begin() {
        isDragging = true; yawVelocity = 0; pitchVelocity = 0; releaseAge = 0
    }
    public func drag(dx: Double, dy: Double, dt: Double) {
        guard isDragging, dx.isFinite, dy.isFinite else { return }
        let elapsed = dt.isFinite ? min(0.1,max(1/240,dt)) : 1/60
        let yawDelta = dx*0.015, pitchDelta = -dy*0.010
        rotation.y += yawDelta
        rotation.x = min(0.55,max(-0.55,rotation.x+pitchDelta))
        yawVelocity = min(5,max(-5,yawDelta/elapsed))
        pitchVelocity = min(2,max(-2,pitchDelta/elapsed))
    }
    public func end() { isDragging = false; releaseAge = 0 }
    public func reset() {
        rotation = Rotation3(); yawVelocity = 0; pitchVelocity = 0
        isDragging = false; releaseAge = 2
    }
    public func update(dt rawDT: Double) {
        guard !isDragging, rawDT.isFinite, rawDT > 0 else { return }
        // Substeps keep the release spring stable across delayed frames and different refresh rates.
        var remaining = min(0.1,rawDT)
        while remaining > 0 {
            let dt = min(1/120,remaining); remaining -= dt; releaseAge += dt
            if releaseAge < 1.4 || !automaticallyReturns {
                yawVelocity *= exp(-dt/0.20); pitchVelocity *= exp(-dt/0.14)
            } else {
                let distance = atan2(sin(rotation.y),cos(rotation.y))
                yawVelocity += (-distance*12-yawVelocity*7)*dt
                pitchVelocity += (-rotation.x*12-pitchVelocity*7)*dt
            }
            rotation.y += yawVelocity*dt
            rotation.x = min(0.55,max(-0.55,rotation.x+pitchVelocity*dt))
        }
        if automaticallyReturns && releaseAge > 1.4 && abs(atan2(sin(rotation.y),cos(rotation.y))) < 0.002 && abs(yawVelocity) < 0.01 {
            rotation.y = (rotation.y/(2 * .pi)).rounded()*2 * .pi; yawVelocity = 0
        }
        if abs(rotation.x) < 0.001 && abs(pitchVelocity) < 0.01 { rotation.x = 0; pitchVelocity = 0 }
    }
}
