import AppKit

if #available(macOS 14.2, *) {
    if CommandLine.arguments.contains("--probe") {
        let capture = SystemAudioCapture()
        do {
            try capture.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let result = capture.latest()
                print("callbacks=\(result.callbackCount) audible=\(result.audibleCallbackCount) energy=\(result.rhythm.energy)")
                capture.dispose()
                exit(result.audibleCallbackCount > 0 ? 0 : 2)
            }
            RunLoop.main.run()
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    } else {
        print("Miho · Tencent Music Hackathon")
    }
} else {
    fputs("Miho requires macOS 14.2 or later.\n", stderr)
    exit(1)
}
