import NetworkExtension
import SwiftUI

struct ContentView: View {
    @State private var vpnManager = VPNManager()
    @State private var showAdvancedConfig = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerStatusCard
                serverPresetsSection
                configurationSection
                feedbackSection
                extensionFooter
            }
            .padding(24)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    // MARK: - Header & Connect Button
    private var headerStatusCard: some View {
        VStack(spacing: 18) {
            // Status Pill
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)

                Text(vpnManager.statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: Capsule())

            // Big Connect / Disconnect Button
            Button {
                Task {
                    await vpnManager.toggleConnection()
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            statusColor.opacity(0.25),
                            lineWidth: 8
                        )
                        .frame(width: 132, height: 132)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [statusColor, statusColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                        .shadow(color: statusColor.opacity(0.35), radius: 12, y: 6)

                    VStack(spacing: 6) {
                        if vpnManager.isTransitioning {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.white)
                        } else {
                            Image(systemName: vpnManager.isConnected ? "lock.shield.fill" : "power")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text(actionButtonLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(vpnManager.isBusy)

            // Duration Timer
            VStack(spacing: 4) {
                Text("DURASI KONEKSI")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.1)

                Text(vpnManager.formattedDuration)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(vpnManager.isConnected ? .primary : .secondary)
                    .contentTransition(.numericText())
            }

            // Quick Connection Details
            Divider()

            HStack(spacing: 0) {
                statItem(
                    title: "Server Endpoint",
                    value: vpnManager.serverAddress,
                    icon: "server.rack"
                )
                Divider()
                    .frame(height: 32)
                statItem(
                    title: "Tunnel IPv4",
                    value: vpnManager.tunnelIP,
                    icon: "network"
                )
                Divider()
                    .frame(height: 32)
                statItem(
                    title: "Paket Dibaca",
                    value: "\(vpnManager.packetsRead)",
                    icon: "arrow.up.arrow.down.circle"
                )
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        )
    }

    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Server Presets
    private var serverPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pilih Lokasi Server")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(VPNServerPreset.presets) { preset in
                    let isSelected = vpnManager.selectedPresetID == preset.id
                    Button {
                        vpnManager.applyPreset(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Text(preset.flag)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(preset.serverAddress)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : cardBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vpnManager.isConnected || vpnManager.isTransitioning)
                }
            }
        }
    }

    // MARK: - Tunnel Configuration Form
    private var configurationSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedConfig) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Server Address") {
                    TextField("103.150.190.10:51820", text: $vpnManager.serverAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                LabeledContent("Tunnel IPv4") {
                    TextField("10.8.0.2", text: $vpnManager.tunnelIP)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                LabeledContent("Subnet Mask") {
                    TextField("255.255.255.0", text: $vpnManager.subnetMask)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                LabeledContent("DNS Servers") {
                    TextField("1.1.1.1, 8.8.8.8", text: $vpnManager.dnsServers)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                Toggle("Rute Semua Trafik (Full Tunnel)", isOn: $vpnManager.routeAllTraffic)

                Divider()

                HStack {
                    Button("Simpan Profil VPN") {
                        Task {
                            _ = await vpnManager.saveConfiguration()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vpnManager.isConnected || vpnManager.isBusy)

                    if vpnManager.isProfileInstalled {
                        Button("Hapus Profil", role: .destructive) {
                            Task {
                                await vpnManager.removeProfile()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(vpnManager.isConnected || vpnManager.isBusy)
                    }

                    Spacer()
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Konfigurasi Packet Tunnel", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text(vpnManager.isProfileInstalled ? "Profil Terpasang" : "Belum Terpasang")
                    .font(.caption)
                    .foregroundStyle(vpnManager.isProfileInstalled ? .green : .secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Status & Error Banners
    @ViewBuilder
    private var feedbackSection: some View {
        if let error = vpnManager.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    vpnManager.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }

        if let message = vpnManager.statusMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    vpnManager.statusMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Footer
    private var extensionFooter: some View {
        HStack {
            Image(systemName: "puzzlepiece.extension.fill")
                .foregroundStyle(.secondary)
            Text("Extension ID: \(vpnManager.extensionBundleIdentifier)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers
    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    private var statusColor: Color {
        switch vpnManager.status {
        case .connected:
            return .green
        case .connecting, .reasserting, .disconnecting:
            return .orange
        case .invalid, .disconnected:
            return .blue
        @unknown default:
            return .gray
        }
    }

    private var actionButtonLabel: String {
        switch vpnManager.status {
        case .connected:
            return "DISCONNECT"
        case .connecting, .reasserting:
            return "STOP"
        case .disconnecting:
            return "WAIT..."
        default:
            return "CONNECT"
        }
    }
}

#Preview {
    ContentView()
}
