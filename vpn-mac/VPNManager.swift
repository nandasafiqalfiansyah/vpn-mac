import Foundation
import NetworkExtension
import Observation

struct VPNServerPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let flag: String
    let serverAddress: String
    let tunnelIP: String
    let dnsServers: String

    static let presets: [VPNServerPreset] = [
        VPNServerPreset(
            id: "id-jkt",
            name: "Jakarta Core",
            region: "Indonesia",
            flag: "🇮🇩",
            serverAddress: "103.150.190.10:51820",
            tunnelIP: "10.8.0.2",
            dnsServers: "1.1.1.1, 8.8.8.8"
        ),
        VPNServerPreset(
            id: "sg-sin",
            name: "Singapore Edge",
            region: "Singapore",
            flag: "🇸🇬",
            serverAddress: "139.99.60.12:51820",
            tunnelIP: "10.8.1.2",
            dnsServers: "1.1.1.1, 1.0.0.1"
        ),
        VPNServerPreset(
            id: "jp-tyo",
            name: "Tokyo High-Speed",
            region: "Japan",
            flag: "🇯🇵",
            serverAddress: "172.104.90.44:51820",
            tunnelIP: "10.8.2.2",
            dnsServers: "1.1.1.1, 8.8.4.4"
        ),
        VPNServerPreset(
            id: "us-sjc",
            name: "San Jose Direct",
            region: "United States",
            flag: "🇺🇸",
            serverAddress: "45.79.110.25:51820",
            tunnelIP: "10.8.3.2",
            dnsServers: "9.9.9.9, 1.1.1.1"
        )
    ]
}

@Observable
final class VPNManager {
    // MARK: - Connection State
    private(set) var status: NEVPNStatus = .disconnected
    private(set) var connectedDate: Date?
    private(set) var elapsedSeconds: Int = 0
    private(set) var isProfileInstalled: Bool = false
    private(set) var isBusy: Bool = false
    private(set) var isSimulatedSession: Bool = false
    var statusMessage: String?
    var errorMessage: String?

    // MARK: - Extension Statistics
    private(set) var packetsRead: UInt64 = 0
    private(set) var bytesRead: UInt64 = 0

    // MARK: - Tunnel Configuration
    var profileName: String = "MacVPN Packet Tunnel"
    var serverAddress: String = "103.150.190.10:51820"
    var tunnelIP: String = "10.8.0.2"
    var subnetMask: String = "255.255.255.0"
    var dnsServers: String = "1.1.1.1, 8.8.8.8"
    var mtu: Int = 1400
    var routeAllTraffic: Bool = true
    var selectedPresetID: String = VPNServerPreset.presets[0].id

    // MARK: - Private Properties
    private var tunnelManager: NETunnelProviderManager?
    private var statusObservationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    var extensionBundleIdentifier: String {
        let hostBundleID = Bundle.main.bundleIdentifier ?? "devplaceholder.LO9XC5F6.MyApp"
        return "\(hostBundleID).PacketTunnelExtension"
    }

    var isConnected: Bool {
        status == .connected
    }

    var isTransitioning: Bool {
        status == .connecting || status == .disconnecting || status == .reasserting || isBusy
    }

    var statusTitle: String {
        switch status {
        case .connected:
            return isSimulatedSession ? "Terhubung (Mode Simulasi)" : "Terhubung (Connected)"
        case .connecting:
            return "Menghubungkan..."
        case .disconnecting:
            return "Memutuskan..."
        case .reasserting:
            return "Menyambung Ulang..."
        case .invalid:
            return "Profil Belum Aktif"
        case .disconnected:
            return "Terputus (Disconnected)"
        @unknown default:
            return "Tidak Diketahui"
        }
    }

    var formattedDuration: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    init() {
        startObservingVPNStatus()
        Task {
            await loadVPNProfile()
        }
    }

    // MARK: - Preset Selection
    func applyPreset(_ preset: VPNServerPreset) {
        selectedPresetID = preset.id
        serverAddress = preset.serverAddress
        tunnelIP = preset.tunnelIP
        dnsServers = preset.dnsServers
    }

    // MARK: - Profile & Connection Management
    func loadVPNProfile() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first {
                tunnelManager = existing
                isProfileInstalled = true
                syncFields(from: existing)
                updateConnectionState(from: existing.connection)
            } else {
                tunnelManager = nil
                isProfileInstalled = false
                status = .disconnected
            }
        } catch {
            // Ignore initial load error on Personal Team builds without NE entitlement
            tunnelManager = nil
            isProfileInstalled = false
        }
    }

    func saveConfiguration() async -> Bool {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }

        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = managers.first ?? NETunnelProviderManager()

            let protocolConfig = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
            protocolConfig.providerBundleIdentifier = extensionBundleIdentifier
            protocolConfig.serverAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            protocolConfig.providerConfiguration = [
                "tunnelIP": tunnelIP.trimmingCharacters(in: .whitespacesAndNewlines),
                "subnetMask": subnetMask.trimmingCharacters(in: .whitespacesAndNewlines),
                "dnsServers": dnsServers.trimmingCharacters(in: .whitespacesAndNewlines),
                "mtu": mtu,
                "routeAllTraffic": routeAllTraffic
            ]

            manager.protocolConfiguration = protocolConfig
            manager.localizedDescription = profileName
            manager.isEnabled = true

            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()

            tunnelManager = manager
            isProfileInstalled = true
            isSimulatedSession = false
            updateConnectionState(from: manager.connection)
            statusMessage = "Konfigurasi VPN berhasil disimpan ke macOS Network Settings."
            return true
        } catch {
            errorMessage = "Gagal menyimpan profil sistem (\(error.localizedDescription)). Menggunakan konfigurasi lokal."
            return false
        }
    }

    func toggleConnection() async {
        errorMessage = nil
        statusMessage = nil

        if status == .connected || status == .connecting || status == .reasserting {
            await disconnect()
        } else {
            await connect()
        }
    }

    func connect() async {
        errorMessage = nil
        statusMessage = nil

        let saved = await saveConfiguration()
        if saved, let manager = tunnelManager {
            do {
                let options: [String: NSObject] = [
                    "startedByApp": NSNumber(value: true)
                ]
                isSimulatedSession = false
                try manager.connection.startVPNTunnel(options: options)
                updateConnectionState(from: manager.connection)
                return
            } catch {
                // Fall back to simulated connection if personal team lacks NE provisioning
            }
        }

        // Fallback simulation when running under Personal Development Team without paid NE capability
        errorMessage = nil
        isSimulatedSession = true
        status = .connecting
        try? await Task.sleep(for: .milliseconds(650))
        connectedDate = Date()
        status = .connected
        statusMessage = "Terhubung dalam Mode Simulasi (Personal Team tidak mendukung provisioning NetworkExtension berbayar)."
        startDurationTimer()
    }

    func disconnect() async {
        if isSimulatedSession {
            status = .disconnecting
            try? await Task.sleep(for: .milliseconds(300))
            status = .disconnected
            isSimulatedSession = false
            connectedDate = nil
            stopDurationTimer()
            statusMessage = "Koneksi VPN dihentikan."
            return
        }

        guard let manager = tunnelManager else {
            status = .disconnected
            stopDurationTimer()
            return
        }
        manager.connection.stopVPNTunnel()
        updateConnectionState(from: manager.connection)
    }

    func removeProfile() async {
        guard let manager = tunnelManager else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await manager.removeFromPreferences()
            tunnelManager = nil
            isProfileInstalled = false
            status = .disconnected
            stopDurationTimer()
            statusMessage = "Profil VPN telah dihapus dari sistem."
        } catch {
            errorMessage = "Gagal menghapus profil VPN: \(error.localizedDescription)"
        }
    }

    // MARK: - Status Observation & Timer
    private func startObservingVPNStatus() {
        statusObservationTask?.cancel()
        statusObservationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: .NEVPNStatusDidChange)
            for await notification in notifications {
                guard let self else { break }
                if let session = notification.object as? NEVPNConnection {
                    self.updateConnectionState(from: session)
                } else if let connection = self.tunnelManager?.connection {
                    self.updateConnectionState(from: connection)
                }
            }
        }
    }

    private func updateConnectionState(from connection: NEVPNConnection) {
        status = connection.status
        connectedDate = connection.connectedDate

        if connection.status == .connected {
            startDurationTimer()
        } else {
            stopDurationTimer()
        }
    }

    private func startDurationTimer() {
        if timerTask != nil { return }

        if connectedDate == nil {
            connectedDate = Date()
        }
        updateElapsedSeconds()

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                self.updateElapsedSeconds()
                if self.isSimulatedSession {
                    self.packetsRead += UInt64.random(in: 4...18)
                    self.bytesRead += UInt64.random(in: 1024...8192)
                } else {
                    await self.pollExtensionStats()
                }
            }
        }
    }

    private func stopDurationTimer() {
        timerTask?.cancel()
        timerTask = nil
        elapsedSeconds = 0
        packetsRead = 0
        bytesRead = 0
    }

    private func updateElapsedSeconds() {
        guard status == .connected else {
            elapsedSeconds = 0
            return
        }
        let start = (isSimulatedSession ? connectedDate : tunnelManager?.connection.connectedDate) ?? connectedDate ?? Date()
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
    }

    private func pollExtensionStats() async {
        guard status == .connected,
              let session = tunnelManager?.connection as? NETunnelProviderSession,
              let requestData = "stats".data(using: .utf8) else {
            return
        }

        await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(requestData) { [weak self] responseData in
                    if let responseData,
                       let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                        let packets = (json["packetsRead"] as? NSNumber)?.uint64Value ?? 0
                        let bytes = (json["bytesRead"] as? NSNumber)?.uint64Value ?? 0
                        Task { @MainActor in
                            self?.packetsRead = packets
                            self?.bytesRead = bytes
                        }
                    }
                    continuation.resume()
                }
            } catch {
                continuation.resume()
            }
        }
    }

    private func syncFields(from manager: NETunnelProviderManager) {
        if let localizedDescription = manager.localizedDescription, !localizedDescription.isEmpty {
            profileName = localizedDescription
        }
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        if let server = proto.serverAddress, !server.isEmpty {
            serverAddress = server
        }
        if let config = proto.providerConfiguration {
            if let ip = config["tunnelIP"] as? String, !ip.isEmpty {
                tunnelIP = ip
            }
            if let mask = config["subnetMask"] as? String, !mask.isEmpty {
                subnetMask = mask
            }
            if let dns = config["dnsServers"] as? String, !dns.isEmpty {
                dnsServers = dns
            }
            if let mtuVal = config["mtu"] as? Int {
                mtu = mtuVal
            }
            if let fullRoute = config["routeAllTraffic"] as? Bool {
                routeAllTraffic = fullRoute
            }
        }
    }
}
