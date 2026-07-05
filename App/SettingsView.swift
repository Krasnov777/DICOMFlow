import SwiftUI

/// App preferences (⌘,). Seeds the default PACS target and built-in SCP.
struct SettingsView: View {
    @AppStorage("defaultHost") private var host = "127.0.0.1"
    @AppStorage("defaultPort") private var port = 4242
    @AppStorage("defaultCalledAE") private var calledAE = "ORTHANC"
    @AppStorage("defaultCallingAE") private var callingAE = "DICOMBENCH"
    @AppStorage("defaultSCPAETitle") private var scpAE = "DICOMBENCH"
    @AppStorage("defaultSCPPort") private var scpPort = 11112
    @AppStorage("inputDevice") private var inputDevice = InputDevice.auto
    @AppStorage("naturalScroll") private var naturalScroll = true
    @AppStorage("rotationMode") private var rotationMode = RotationMode.arcball
    @AppStorage("networkTimeout") private var networkTimeout = 15
    @AppStorage("tlsVerify") private var tlsVerify = false
    @AppStorage("tlsCAPath") private var tlsCAPath = ""

    var body: some View {
        TabView {
            pacs.tabItem { Label("PACS", systemImage: "network") }
            interaction.tabItem { Label("Interaction", systemImage: "hand.point.up.left") }
            acknowledgements.tabItem { Label("Acknowledgements", systemImage: "text.badge.checkmark") }
        }
        .frame(width: 470, height: 360)
    }

    private struct Credit: Identifiable {
        let name, detail, license, url: String
        var id: String { name }
    }

    private static let credits: [Credit] = [
        Credit(name: "DCMTK", detail: "DICOM Toolkit — OFFIS e.V.",
               license: "BSD 3-Clause", url: "https://github.com/DCMTK/dcmtk"),
        Credit(name: "OpenJPEG", detail: "JPEG 2000 codec — UCL and contributors",
               license: "BSD 2-Clause", url: "https://github.com/uclouvain/openjpeg"),
        Credit(name: "fmjpeg2koj", detail: "JPEG 2000 pipeline for DCMTK — Ing-Long Eric Kuo",
               license: "Apache 2.0", url: "https://github.com/DraconPern/fmjpeg2koj"),
        Credit(name: "OpenSSL", detail: "TLS toolkit — The OpenSSL Project Authors",
               license: "Apache 2.0", url: "https://www.openssl.org"),
        Credit(name: "zlib", detail: "Compression — Jean-loup Gailly & Mark Adler",
               license: "zlib License", url: "https://zlib.net"),
    ]

    private var acknowledgements: some View {
        Form {
            Section {
                ForEach(Self.credits) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.name).fontWeight(.semibold)
                            Spacer()
                            Text(c.license).foregroundStyle(.secondary)
                        }
                        Text(c.detail).font(.callout).foregroundStyle(.secondary)
                        if let u = URL(string: c.url) {
                            Link(c.url, destination: u).font(.callout)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Open-source components")
            } footer: {
                Text("DicomFlow is MIT-licensed open source. Full third-party license texts ship in THIRD-PARTY-NOTICES.md alongside the source.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private var pacs: some View {
        Form {
            Section("Default PACS target") {
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number.grouping(.never))
                TextField("Called AE", text: $calledAE)
                TextField("Calling AE", text: $callingAE)
            }
            Section("Built-in Test SCP") {
                TextField("AE Title", text: $scpAE)
                TextField("Port", value: $scpPort, format: .number.grouping(.never))
            }
            Section {
                TextField("Timeout (seconds)", value: $networkTimeout, format: .number.grouping(.never))
                    .onChange(of: networkTimeout) { _, _ in DicomEngine.applyNetworkTimeout() }
                Toggle("Verify TLS certificates", isOn: $tlsVerify)
                    .onChange(of: tlsVerify) { _, _ in DicomEngine.applyTLSConfig() }
                TextField("Trusted CA file (PEM, optional)", text: $tlsCAPath)
                    .onChange(of: tlsCAPath) { _, _ in DicomEngine.applyTLSConfig() }
            } header: {
                Text("Networking")
            } footer: {
                Text("Timeout applies to TCP connect, association negotiation, and each DIMSE message — and to DICOMweb/FHIR requests. 0 disables (waits forever).\n\nTLS per target is toggled in each tool's target form; the options above control certificate verification (off = accept any certificate — fine for test setups).")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private var interaction: some View {
        Form {
            Section {
                Picker("Input device", selection: $inputDevice) {
                    ForEach(InputDevice.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Natural scroll direction", isOn: $naturalScroll)
            } header: {
                Text("Pointing device")
            } footer: {
                Text("Automatic adapts per gesture. Trackpad tunes scroll/zoom for high-resolution two-finger input; Mouse expects discrete wheel notches.\n\nViewer gestures — drag: window/level (2D) or orbit (3D) · ⌥-drag: pan · scroll: change slice (2D) / zoom (3D) · pinch: zoom.")
                    .font(.callout)
            }
            Section {
                Picker("3D rotation", selection: $rotationMode) {
                    ForEach(RotationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } header: {
                Text("3D volume")
            } footer: {
                Text("Arcball grabs the surface and turns it freely (can tilt off-axis on diagonal drags). Turntable keeps the volume upright — horizontal spins around the vertical axis, vertical tilts — which feels more controlled, especially on a trackpad.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
