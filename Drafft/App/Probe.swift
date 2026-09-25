import Foundation

/// Temporary diagnostics, active only with the `-probe` launch argument: logs every main-thread
/// block over 50 ms, with the uptime, so hangs can be matched to what the app was doing.
enum Probe {
    static let on = ProcessInfo.processInfo.arguments.contains("-probe")

    static func start() {
        guard on else { return }
        let t = Thread {
            while true {
                let sem = DispatchSemaphore(value: 0)
                let start = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let d = ProcessInfo.processInfo.systemUptime - start
                if d > 0.05 { log(String(format: "PROBE HANG %4.0f ms ending at %.3f", d * 1000, ProcessInfo.processInfo.systemUptime)) }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        t.qualityOfService = .userInteractive
        t.start()
    }

    static func mark(_ s: String) {
        guard on else { return }
        log(String(format: "PROBE %@ at %.3f", s, ProcessInfo.processInfo.systemUptime))
    }

    /// Unbuffered, so lines arrive in order even when the output goes to a file.
    private static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
