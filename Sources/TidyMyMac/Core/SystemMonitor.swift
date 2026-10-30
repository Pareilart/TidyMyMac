import AppKit
import Darwin
import Foundation
import IOKit.ps

struct BatteryInfo {
    let percent: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    /// Minutes avant vide (sur batterie) ou avant charge complète (en charge).
    let minutesRemaining: Int?
}

struct ConnectedVolume: Identifiable {
    let url: URL
    let name: String
    let free: Int64
    let total: Int64
    var id: URL { url }
}

enum SpeedTestState: Equatable {
    case idle
    case running
    case finished(downloadMbps: Double, uploadMbps: Double)
    case failed
}

/// Mesures en direct pour le panneau de la barre des menus, rafraîchies toutes les 2 secondes.
@MainActor
final class SystemMonitor: ObservableObject {
    enum Health { case good, watch, critical }

    @Published private(set) var disk = DiskInfo.current()
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var memoryPressure: Int32 = 1
    @Published private(set) var cpuLoad: Double = 0
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var downloadHistory: [Double] = Array(repeating: 0, count: 40)
    @Published private(set) var volumes: [ConnectedVolume] = []
    @Published var speedTest: SpeedTestState = .idle
    @Published var memoryFreeing = false
    @Published private(set) var memoryGainText: String?

    private static let interval: TimeInterval = 2
    nonisolated private static let host = mach_host_self()
    private var timer: Timer?
    private var previousCPUTicks: [UInt64]?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?
    /// Valeurs fictives figées pour les captures d'écran du README.
    private var isDemo = false

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    func showDemo() {
        isDemo = true
        disk = DiskInfo(total: 1_000_000_000_000, free: 412_000_000_000)
        memoryTotal = 17_179_869_184
        memoryUsed = 9_800_000_000
        memoryPressure = 1
        cpuLoad = 0.18
        thermalState = .nominal
        battery = BatteryInfo(percent: 76, isCharging: false, isPluggedIn: false, minutesRemaining: 252)
        downloadRate = 2_400_000
        uploadRate = 310_000
        downloadHistory = (0..<40).map { index in
            abs(sin(Double(index) / 4)) * 2_000_000 + Double(index % 7) * 120_000
        }
        volumes = [ConnectedVolume(
            url: URL(fileURLWithPath: "/Volumes/Archives"), name: "Archives",
            free: 1_240_000_000_000, total: 2_000_000_000_000
        )]
    }

    var issues: [String] {
        var found: [String] = []
        if let disk, Double(disk.free) / Double(max(disk.total, 1)) < 0.10 { found.append(localized("Disque presque plein")) }
        if memoryPressure >= 4 { found.append(localized("Mémoire saturée")) } else if memoryPressure >= 2 { found.append(localized("Mémoire sous tension")) }
        if thermalState == .serious || thermalState == .critical { found.append(localized("Le Mac chauffe")) }
        if let battery, battery.percent < 15, !battery.isPluggedIn { found.append(localized("Batterie faible")) }
        return found
    }

    var health: Health {
        if memoryPressure >= 4 || thermalState == .critical { return .critical }
        return issues.isEmpty ? .good : .watch
    }

    func start() {
        guard timer == nil, !isDemo else { return }
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        disk = DiskInfo.current()
        thermalState = ProcessInfo.processInfo.thermalState
        battery = Self.readBattery()
        volumes = Self.readVolumes()
        memoryPressure = Self.readMemoryPressure()
        if let memory = Self.readMemoryUsed() { memoryUsed = memory }

        if let ticks = Self.readCPUTicks() {
            if let previous = previousCPUTicks {
                let delta = zip(ticks, previous).map { $0 >= $1 ? $0 - $1 : 0 }
                let total = delta.reduce(0, +)
                // Ordre des compteurs : utilisateur, système, inactif, nice.
                if total > 0 { cpuLoad = Double(total - delta[2]) / Double(total) }
            }
            previousCPUTicks = ticks
        }

        let network = Self.readNetworkBytes()
        let now = Date()
        if let previous = previousNetwork {
            let elapsed = max(now.timeIntervalSince(previous.date), 0.1)
            // Les compteurs d'interface sont sur 32 bits : on ignore un tour de compteur.
            downloadRate = network.received >= previous.received ? Double(network.received - previous.received) / elapsed : 0
            uploadRate = network.sent >= previous.sent ? Double(network.sent - previous.sent) / elapsed : 0
            downloadHistory = Array((downloadHistory + [downloadRate]).suffix(40))
        }
        previousNetwork = (network.received, network.sent, now)
    }

    func freeMemory() {
        memoryFreeing = true
        memoryGainText = nil
        Task {
            let gain = await Task.detached { () -> UInt64? in
                let before = SystemMonitor.readFreeMemory() ?? 0
                guard Shell.admin("/usr/sbin/purge").status == 0 else { return nil }
                let after = SystemMonitor.readFreeMemory() ?? 0
                return after > before ? after - before : 0
            }.value
            if let gain {
                memoryGainText = gain > 0 ? localized("\(Int64(gain).formattedBytes) libérés") : "Déjà optimisée"
                ActivityJournal.shared.record(JournalEntry(kind: .memory, memoryFreed: Int64(gain)))
            }
            memoryFreeing = false
            refresh()
        }
    }

    func runSpeedTest() {
        speedTest = .running
        Task {
            let output = await Task.detached { Shell.run("/usr/bin/networkQuality", ["-c", "-M", "20"]).output }.value
            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let download = (json["dl_throughput"] as? NSNumber)?.doubleValue,
                  let upload = (json["ul_throughput"] as? NSNumber)?.doubleValue else {
                speedTest = .failed
                return
            }
            speedTest = .finished(downloadMbps: download / 1_000_000, uploadMbps: upload / 1_000_000)
        }
    }

    func eject(_ volume: ConnectedVolume) {
        Task {
            _ = await Task.detached { try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url) }.value
            refresh()
        }
    }

    // MARK: - Lectures système

    nonisolated private static func readVMStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    nonisolated private static var pageSize: UInt64 { UInt64(sysconf(_SC_PAGESIZE)) }

    private static func readMemoryUsed() -> UInt64? {
        guard let stats = readVMStatistics() else { return nil }
        // Même définition que le Moniteur d'activité : mémoire des apps + câblée + compressée.
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        return (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
    }

    /// Mémoire entièrement libre : c'est elle qui augmente après une purge du cache disque.
    nonisolated static func readFreeMemory() -> UInt64? {
        guard let stats = readVMStatistics() else { return nil }
        return UInt64(stats.free_count) * pageSize
    }

    /// 1 = normale, 2 = avertissement, 4 = critique.
    nonisolated static func readMemoryPressure() -> Int32 {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return level
    }

    private static func readCPUTicks() -> [UInt64]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return [UInt64(ticks.0), UInt64(ticks.1), UInt64(ticks.2), UInt64(ticks.3)]
    }

    /// Octets reçus et envoyés sur les interfaces Wi-Fi et Ethernet (en*).
    private static func readNetworkBytes() -> (received: UInt64, sent: UInt64) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: interface.ifa_name).hasPrefix("en"),
                  let data = interface.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        return (received, sent)
    }

    private static func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryInfo(
                percent: current * 100 / maximum,
                isCharging: charging,
                isPluggedIn: pluggedIn,
                minutesRemaining: (minutes ?? 0) > 0 ? minutes : nil
            )
        }
        return nil
    }

    private static func readVolumes() -> [ConnectedVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> ConnectedVolume? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsInternal == false || values.volumeIsEjectable == true else { return nil }
            return ConnectedVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                free: Int64(values.volumeAvailableCapacity ?? 0),
                total: Int64(values.volumeTotalCapacity ?? 0)
            )
        }
    }
}
