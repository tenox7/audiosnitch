import Foundation
import CoreAudio

struct AudioProcess: Hashable {
    let pid: pid_t
    let bundleID: String
    let isRunningOutput: Bool

    var appName: String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    func hash(into hasher: inout Hasher) { hasher.combine(pid) }
    static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool { lhs.pid == rhs.pid }
}

enum AudioProperty {
    static func uint32(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func int32(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    static func objectIDs(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var data = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &data) == noErr else { return [] }
        return data
    }
}

class AudioMonitor {
    private var activeProcesses = Set<AudioProcess>()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func getProcesses() -> [AudioProcess] {
        AudioProperty.objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).compactMap { objID in
            guard let pid = AudioProperty.int32(objID, kAudioProcessPropertyPID),
                  let bundleID = AudioProperty.string(objID, kAudioProcessPropertyBundleID) else { return nil }
            let isRunning = AudioProperty.uint32(objID, kAudioProcessPropertyIsRunningOutput) == 1
            return AudioProcess(pid: pid, bundleID: bundleID, isRunningOutput: isRunning)
        }
    }

    func log(_ msg: String) {
        print("[\(dateFormatter.string(from: Date()))] \(msg)")
        fflush(stdout)
    }

    func poll() {
        let outputting = getProcesses().filter { $0.isRunningOutput }
        let currentPIDs = Set(outputting.map { $0.pid })
        let previousPIDs = Set(activeProcesses.map { $0.pid })

        for proc in outputting where !previousPIDs.contains(proc.pid) {
            log("🔊 START: \(proc.appName) (pid: \(proc.pid), bundle: \(proc.bundleID))")
        }
        for proc in activeProcesses where !currentPIDs.contains(proc.pid) {
            log("🔇 STOP:  \(proc.appName) (pid: \(proc.pid), bundle: \(proc.bundleID))")
        }
        activeProcesses = Set(outputting)
    }

    func run() {
        log("Audio Snitch - monitoring audio output (Ctrl+C to stop)")

        let initial = getProcesses().filter { $0.isRunningOutput }
        if !initial.isEmpty {
            log("Currently playing:")
            initial.forEach { log("  • \(self.formatProcess($0))") }
            activeProcesses = Set(initial)
        }

        while true {
            Thread.sleep(forTimeInterval: 0.5)
            poll()
        }
    }

    private func formatProcess(_ proc: AudioProcess) -> String {
        "\(proc.appName) (pid: \(proc.pid))"
    }
}

if CommandLine.arguments.contains("-h") || CommandLine.arguments.contains("--help") {
    print("""
    audiosnitch - Monitor which apps are outputting audio on macOS

    Usage: audiosnitch [options]

    Options:
      -h, --help    Show this help message

    Requires macOS 14.2+ (Sonoma). Uses CoreAudio process objects API.
    """)
    exit(0)
}

AudioMonitor().run()
