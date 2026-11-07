import Foundation
import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "PacketTunnelExtension", category: "Tunnel")
    private var isReadingPackets = false
    private var connectedAt: Date?
    private var packetsReadCount: UInt64 = 0
    private var bytesReadCount: UInt64 = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting Packet Tunnel...")

        let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol
        let providerConfig = tunnelProtocol?.providerConfiguration

        let remoteAddress = tunnelProtocol?.serverAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRemoteAddress = (remoteAddress?.isEmpty == false ? remoteAddress! : "198.51.100.1")

        let tunnelIP = (providerConfig?["tunnelIP"] as? String) ?? "10.8.0.2"
        let subnetMask = (providerConfig?["subnetMask"] as? String) ?? "255.255.255.0"
        let dnsString = (providerConfig?["dnsServers"] as? String) ?? "1.1.1.1, 8.8.8.8"
        let routeAllTraffic = (providerConfig?["routeAllTraffic"] as? Bool) ?? true
        let mtuValue = (providerConfig?["mtu"] as? Int) ?? 1400

        let dnsServers = dnsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: effectiveRemoteAddress)

        // Configure IPv4 settings and routing
        let ipv4Settings = NEIPv4Settings(addresses: [tunnelIP], subnetMasks: [subnetMask])
        if routeAllTraffic {
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        } else {
            ipv4Settings.includedRoutes = [
                NEIPv4Route(destinationAddress: "10.8.0.0", subnetMask: "255.255.255.0")
            ]
        }
        networkSettings.ipv4Settings = ipv4Settings

        // Configure DNS settings
        let effectiveDNS = dnsServers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : dnsServers
        let dnsSettings = NEDNSSettings(servers: effectiveDNS)
        dnsSettings.matchDomains = [""]
        networkSettings.dnsSettings = dnsSettings

        networkSettings.mtu = NSNumber(value: mtuValue)

        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            if let error {
                self?.logger.error("Failed to apply tunnel network settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            self?.connectedAt = Date()
            self?.packetsReadCount = 0
            self?.bytesReadCount = 0
            self?.isReadingPackets = true
            self?.readPacketsLoop()
            self?.logger.info("Packet Tunnel started successfully (IP: \(tunnelIP))")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping Packet Tunnel (reason: \(String(describing: reason.rawValue)))")
        isReadingPackets = false
        connectedAt = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }

        let response: [String: Any] = [
            "isRunning": isReadingPackets,
            "connectedAt": connectedAt?.timeIntervalSince1970 ?? 0,
            "packetsRead": packetsReadCount,
            "bytesRead": bytesReadCount
        ]

        let data = try? JSONSerialization.data(withJSONObject: response)
        completionHandler(data)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        logger.info("Packet Tunnel entering sleep mode")
        completionHandler()
    }

    override func wake() {
        logger.info("Packet Tunnel waking up")
    }

    private func readPacketsLoop() {
        guard isReadingPackets else { return }

        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, self.isReadingPackets else { return }

            self.packetsReadCount += UInt64(packets.count)
            for packet in packets {
                self.bytesReadCount += UInt64(packet.count)
            }

            // Continue reading packets from the virtual interface
            self.readPacketsLoop()
        }
    }
}
