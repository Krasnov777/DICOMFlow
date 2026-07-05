import SwiftUI

@main
struct DicomFlowApp: App {
    @StateObject private var state = AppState()
    @StateObject private var profiles = PacsProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(state.engine)
                .environmentObject(state.viewerState)
                .environmentObject(profiles)
                // Small enough to sit in a split-screen half; the viewer's bottom
                // bar scrolls horizontally rather than clipping when it's narrower
                // than the toolbar (windowResizability(.contentMinSize)).
                .frame(minWidth: 820, minHeight: 600)
                .task {
                    // Headless test hooks are development-only; Release boots straight in.
                    #if DEBUG
                    let env = ProcessInfo.processInfo.environment
                    if let f = env["DICOMFLOW_NATIVE_TAGS"] {
                        NativeTest.runTags(path: f)
                    } else if let dir = env["DICOMFLOW_NATIVE_EDITANON"] {
                        await NativeTest.runEditAnon(directory: dir)
                    } else if let dir = env["DICOMFLOW_NATIVE_NET"] {
                        await NativeTest.runNet(directory: dir)
                    } else if let t = env["DICOMFLOW_NATIVE_SCU"] {
                        await NativeTest.runScu(target: t, directory: env["DICOMFLOW_DIR"] ?? "/tmp/dicomflow_fixture")
                    } else if env["DICOMFLOW_NATIVE_SCPONLY"] != nil {
                        await NativeTest.runScpOnly()
                    } else if let dir = env["DICOMFLOW_SCAN"] {
                        await NativeTest.runScan(directory: dir)
                    } else if env["DICOMFLOW_ROTATE"] != nil {
                        await NativeTest.runRotate()
                    } else if let d = env["DICOMFLOW_MOVIE"] {
                        await NativeTest.runMovie(directory: d)
                    } else if env["DICOMFLOW_TLSTEST"] != nil {
                        await NativeTest.runTLS()
                    } else if let d = env["DICOMFLOW_ROI"] {
                        await NativeTest.runROI(directory: d)
                    } else if let f = env["DICOMFLOW_DECODE"] {
                        await NativeTest.runDecode(path: f)
                    } else if env["DICOMFLOW_QR"] != nil {
                        await NativeTest.runQR()
                    } else if env["DICOMFLOW_KEYCHAIN"] != nil {
                        await NativeTest.runKeychain()
                    } else if env["DICOMFLOW_TIMEOUT"] != nil {
                        await NativeTest.runTimeout()
                    } else if let f = env["DICOMFLOW_PCAP"] {
                        await NativeTest.runPcap(path: f)
                    } else if env["DICOMFLOW_FHIR"] != nil {
                        await NativeTest.runFHIR()
                    } else if let f = env["DICOMFLOW_VALIDATE"] {
                        await NativeTest.runValidate(path: f)
                    } else if env["DICOMFLOW_HL7"] != nil {
                        await NativeTest.runHL7()
                    } else if env["DICOMFLOW_MWL"] != nil {
                        await NativeTest.runMWL()
                    } else if env["DICOMFLOW_PROTO"] != nil {
                        await NativeTest.runProto()
                    } else if env["DICOMFLOW_DICOMWEB"] != nil {
                        await NativeTest.runDicomWeb()
                    } else if let dir = env["DICOMFLOW_SR"] {
                        await NativeTest.runSR(directory: dir)
                    } else if let dir = env["DICOMFLOW_PERF"] {
                        await NativeTest.runPerf(directory: dir)
                    } else if let t = env["DICOMFLOW_ORTHANC"] {
                        await NativeTest.runOrthanc(target: t, seedDir: env["DICOMFLOW_DIR"] ?? "/tmp/dicomflow_fixture")
                    } else if let dir = env["DICOMFLOW_NATIVE_VOLUME"] {
                        let out = env["DICOMFLOW_RENDER_OUT"] ?? NSTemporaryDirectory() + "dicomflow_native"
                        await NativeTest.runVolume(directory: dir, outDir: out)
                    } else {
                        state.boot()
                    }
                    #else
                    state.boot()
                    #endif
                }
        }
        .windowResizability(.contentMinSize)
        .commands { DicomFlowCommands(state: state) }

        Settings { SettingsView() }
    }
}
