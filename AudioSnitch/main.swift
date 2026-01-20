import SwiftUI
import CoreAudio

func getProcessName(_ pid: pid_t) -> String? {
    let name = UnsafeMutablePointer<CChar>.allocate(capacity: 1024)
    defer { name.deallocate() }
    let result = proc_name(pid, name, 1024)
    guard result > 0 else { return nil }
    return String(cString: name)
}

struct AudioEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: EventType
    let appName: String
    let bundleID: String
    let pid: pid_t

    enum EventType {
        case start, stop
        var icon: String { self == .start ? "🔊" : "🔇" }
        var label: String { self == .start ? "START" : "STOP" }
    }

    var displayName: String {
        if appName == "systemsoundserverd" { return "System Sound Effects" }
        return appName
    }
}

struct AudioProcess: Hashable {
    let pid: pid_t
    let bundleID: String
    let isRunningOutput: Bool

    var appName: String {
        if !bundleID.isEmpty {
            if let last = bundleID.split(separator: ".").last { return String(last) }
            return bundleID
        }
        return getProcessName(pid) ?? "pid:\(pid)"
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

@MainActor
class AudioMonitor: ObservableObject {
    @Published var events: [AudioEvent] = []
    @Published var activeProcesses: Set<AudioProcess> = []
    private var timer: Timer?

    func start() {
        let initial = getProcesses().filter { $0.isRunningOutput }
        activeProcesses = Set(initial)
        for proc in initial {
            events.insert(AudioEvent(timestamp: Date(), type: .start, appName: proc.appName, bundleID: proc.bundleID, pid: proc.pid), at: 0)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        events.removeAll()
    }

    private func getProcesses() -> [AudioProcess] {
        AudioProperty.objectIDs(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).compactMap { objID in
            guard let pid = AudioProperty.int32(objID, kAudioProcessPropertyPID) else { return nil }
            let bundleID = AudioProperty.string(objID, kAudioProcessPropertyBundleID) ?? ""
            let isRunning = AudioProperty.uint32(objID, kAudioProcessPropertyIsRunningOutput) == 1
            return AudioProcess(pid: pid, bundleID: bundleID, isRunningOutput: isRunning)
        }
    }

    private func poll() {
        let outputting = getProcesses().filter { $0.isRunningOutput }
        let currentPIDs = Set(outputting.map { $0.pid })
        let previousPIDs = Set(activeProcesses.map { $0.pid })

        for proc in outputting where !previousPIDs.contains(proc.pid) {
            events.insert(AudioEvent(timestamp: Date(), type: .start, appName: proc.appName, bundleID: proc.bundleID, pid: proc.pid), at: 0)
        }
        for proc in activeProcesses where !currentPIDs.contains(proc.pid) {
            events.insert(AudioEvent(timestamp: Date(), type: .stop, appName: proc.appName, bundleID: proc.bundleID, pid: proc.pid), at: 0)
        }
        activeProcesses = Set(outputting)
    }
}

struct ContentView: View {
    @StateObject private var monitor = AudioMonitor()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if monitor.events.isEmpty {
                Spacer()
                Text("Waiting for audio events...")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(monitor.events) { event in
                        HStack {
                            Text(event.type.icon)
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text(event.displayName)
                                    .font(.headline)
                                Text("\(event.bundleID) PID=\(event.pid)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(event.type.label)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(event.type == .start ? .green : .orange)
                                Text(dateFormatter.string(from: event.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .id(event.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: monitor.events.first?.id) { _, newID in
                        if let id = newID { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }

            Divider()

            HStack {
                Circle()
                    .fill(monitor.activeProcesses.isEmpty ? Color.gray : Color.green)
                    .frame(width: 10, height: 10)
                Text(monitor.activeProcesses.isEmpty ? "No audio" : "\(monitor.activeProcesses.count) active")
                    .font(.headline)
                Spacer()
                Button("Clear") { monitor.clear() }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 300)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

@main
struct AudioSnitchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
