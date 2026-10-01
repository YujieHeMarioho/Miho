import SwiftUI
import MihoCore

/// A transparent, continuous vocal spectrum outline around the round body.
/// No plate, scrolling graph, drum spectrum or free-running animation.
struct AudioReactiveField: View {
    var frame: SoundFieldFrame
    var pose: DancePose
    var appearance: CharacterAppearance
    var body: some View {
        Canvas { context,size in draw(context,size: size) }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func draw(_ input: GraphicsContext,size: CGSize) {
        var context = input
        let pixelsPerUnit = Double(size.height)/(2*CharacterScene.cameraScale)
        let tilt = atan(0.5/7.0)
        let center = CGPoint(x: Double(size.width)/2+pose.x*pixelsPerUnit,
                             y: Double(size.height)/2+((1.25-1.02-pose.y)*cos(tilt)+pose.z*sin(tilt))*pixelsPerUnit)
        let radii = appearance.shape.radii
        // Include the headset and ears so the outline remains visible
        // around the whole mascot, rather than disappearing behind it.
        let radius = max(1.32,max(radii.0,radii.1)+0.35)*pose.scale*pixelsPerUnit+max(4,pixelsPerUnit*0.075)
        let count = 96
        var points: [CGPoint] = []
        for index in 0..<count {
            let band = Double(index)/Double(count)*24
            let lower = Int(band)%24, fraction = band-floor(band)
            func level(_ i: Int) -> Double {
                let j = (i+24)%24
                return (frame.vocalSpectrum[(j+23)%24]+2*frame.vocalSpectrum[j]+frame.vocalSpectrum[(j+1)%24])/4
            }
            let value = level(lower)*(1-fraction)+level(lower+1)*fraction
            let distance = radius+pixelsPerUnit*(0.025*frame.drive+0.09*value)
            let angle = Double(index)/Double(count)*2*Double.pi-Double.pi/2
            let point = CGPoint(x: center.x+distance*cos(angle),y: center.y+distance*sin(angle))
            points.append(point)
        }
        var path = Path()
        path.move(to: points[0])
        // Periodic cubic interpolation makes a smooth seam and avoids
        // turning 24 FFT bands into a ring of jagged spokes.
        for i in 0..<count {
            let a = points[(i+count-1)%count], b = points[i]
            let c = points[(i+1)%count], d = points[(i+2)%count]
            path.addCurve(to: c,
                          control1: CGPoint(x: b.x+(c.x-a.x)/6,y: b.y+(c.y-a.y)/6),
                          control2: CGPoint(x: c.x-(d.x-b.x)/6,y: c.y-(d.y-b.y)/6))
        }
        path.closeSubpath()
        let tint = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color(red: 0.48,green: 0.78,blue: 0.98),Color(red: 0.69,green: 0.52,blue: 1)]),
            startPoint: CGPoint(x: center.x-radius,y: center.y-radius),
            endPoint: CGPoint(x: center.x+radius,y: center.y+radius))
        var glow = context
        glow.opacity = 0.10+frame.drive*0.08
        glow.addFilter(.blur(radius: 2))
        glow.stroke(path,with: tint,lineWidth: 3)
        context.opacity = 0.45+frame.drive*0.20
        context.stroke(path,with: tint,style: StrokeStyle(lineWidth: 1.2,lineCap: .round,lineJoin: .round))
    }
}
