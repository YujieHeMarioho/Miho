import SwiftUI
import MihoCore

/// Spectrum and scrolling amplitude envelopes from the same captured sound as
/// the dancer. There is deliberately no animation timer or synthetic sine wave.
struct AudioReactiveField: View {
    var frame: SoundFieldFrame
    private let cyan = Color(red: 0.20,green: 0.91,blue: 0.96)
    private let coral = Color(red: 1,green: 0.42,blue: 0.64)
    var body: some View {
        Canvas { context,size in
            drawBackground(context,size: size)
            drawSpectrum(context,size: size)
            drawEnvelopes(context,size: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24,style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24,style: .continuous).stroke(.white.opacity(0.09),lineWidth: 1) }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func drawBackground(_ context: GraphicsContext,size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let bounds = CGRect(origin: .zero,size: size)
        context.fill(Path(bounds),with: .linearGradient(
            Gradient(colors: [Color(red: 0.035,green: 0.06,blue: 0.15),Color(red: 0.13,green: 0.055,blue: 0.23)]),
            startPoint: .zero,endPoint: CGPoint(x: w,y: h)))
        let center = CGPoint(x: w*0.5,y: h*0.46)
        let radius = min(w*0.36,h*0.31)
        context.fill(Path(ellipseIn: CGRect(x: center.x-radius*1.5,y: center.y-radius*1.5,width: radius*3,height: radius*3)),
            with: .radialGradient(Gradient(colors: [cyan.opacity(0.06+frame.drive*0.25),.clear]),
                                  center: center,startRadius: 0,endRadius: radius*1.5))
        var grid = Path()
        for i in 1..<10 {
            let x = w*CGFloat(i)/10
            grid.move(to: CGPoint(x: x,y: 0));grid.addLine(to: CGPoint(x: x,y: h))
        }
        for i in 1..<12 {
            let y = h*CGFloat(i)/12
            grid.move(to: CGPoint(x: 0,y: y));grid.addLine(to: CGPoint(x: w,y: y))
        }
        context.stroke(grid,with: .color(cyan.opacity(0.045+frame.drive*0.055)),lineWidth: 0.5)
        let halo = Path(ellipseIn: CGRect(x: center.x-radius,y: center.y-radius,width: radius*2,height: radius*2))
        context.stroke(halo,with: .color(cyan.opacity(0.12+frame.voice*0.20)),lineWidth: 1)
    }
    private func drawSpectrum(_ context: GraphicsContext,size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let center = CGPoint(x: w*0.5,y: h*0.46)
        let radius = min(w*0.36,h*0.31)
        for i in 0..<24 {
            let level = frame.spectrum[i]
            let angle = Double(i)/24*2*Double.pi-Double.pi/2
            let inner = radius+4
            let outer = inner+2+min(w*0.10,24)*level
            var bar = Path()
            bar.move(to: CGPoint(x: center.x+inner*cos(angle),y: center.y+inner*sin(angle)))
            bar.addLine(to: CGPoint(x: center.x+outer*cos(angle),y: center.y+outer*sin(angle)))
            let color = frame.vocalSpectrum[i] >= frame.drumSpectrum[i] ? cyan : coral
            context.stroke(bar,with: .color(color.opacity(0.20+level*0.75)),style: StrokeStyle(lineWidth: max(2,w/110),lineCap: .round))
        }
        for i in 0..<24 {
            let rect = CGRect(x: w*0.07+Double(i)*w*0.86/24,y: h*0.965,width: max(1,w*0.86/24-2),height: 3)
            context.fill(Path(roundedRect: rect,cornerRadius: 1),with: .color(cyan.opacity(0.10+frame.spectrum[i]*0.85)))
        }
    }
    private func drawEnvelopes(_ context: GraphicsContext,size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        // Recent real vocal amplitude above and below a center line.
        let mid = h*0.83, amplitude = h*0.15
        for side in [-1.0,1.0] {
            let path = curve(frame.vocals,size: size,baseline: mid,amplitude: amplitude*side/0.70)
            context.stroke(path,with: .linearGradient(Gradient(colors: [cyan.opacity(0.08),cyan.opacity(0.95)]),
                                                     startPoint: .zero,endPoint: CGPoint(x: w,y: 0)),
                           style: StrokeStyle(lineWidth: 1.6,lineCap: .round,lineJoin: .round))
        }
        let drumPath = curve(frame.drums,size: size,baseline: h*0.91,amplitude: -h*0.10)
        context.stroke(drumPath,with: .linearGradient(Gradient(colors: [coral.opacity(0.04),coral.opacity(0.78)]),
                                                     startPoint: .zero,endPoint: CGPoint(x: w,y: 0)),
                       style: StrokeStyle(lineWidth: 1.2,lineCap: .round,lineJoin: .round))
    }
    private func curve(_ values: [Double],size: CGSize,baseline: Double,amplitude: Double) -> Path {
        let points = values.enumerated().map { index,value in
            CGPoint(x: size.width*(0.07+0.86*Double(index)/Double(max(1,values.count-1))),
                    y: baseline-min(1,max(0,value))*amplitude)
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            let midpoint = CGPoint(x: (points[i-1].x+points[i].x)/2,y: (points[i-1].y+points[i].y)/2)
            path.addQuadCurve(to: midpoint,control: points[i-1])
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}
