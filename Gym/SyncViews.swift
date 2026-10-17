import SwiftData
import SwiftUI
#if os(macOS)
import CoreImage.CIFilterBuiltins
#endif

// Settings for keeping the Mac and the iPhone in step (Sync.swift).

#if os(macOS)
/// On the Mac: turn sync on and show the iPhone how to connect.
struct SyncSection: View {
    @ObservedObject private var server = SyncServer.shared
    @AppStorage("lastPhoneSync") private var lastPhoneSync: Double = 0
    @State private var confirmNewCode = false

    var body: some View {
        Section {
            Toggle("Sync with your iPhone", isOn: Binding(get: { server.enabled }, set: { server.enabled = $0 }))
            if server.enabled {
                if let e = server.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.warning)
                }
                TextField("This Mac's address", text: Binding(get: { server.address }, set: { server.address = $0 }),
                          prompt: Text("https://your-mac.your-tailnet.ts.net:8443"))
                LabeledContent("Pairing code") {
                    HStack {
                        Text(server.code).font(.bodyText.monospaced()).foregroundStyle(.primary).textSelection(.enabled)
                        Button("New code…") { confirmNewCode = true }
                    }
                }
                LabeledContent("Last synced", value: lastPhoneSync > 0 ? relative(Date(timeIntervalSince1970: lastPhoneSync)) : "Not yet")
                if !server.address.isEmpty, let qr = qrImage("gymsync:\(SyncClient.normalise(server.address))#\(server.code)") {
                    HStack {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 220, height: 220)
                            .padding(Space.m).background(Tokens.paper, in: RoundedRectangle(cornerRadius: Radius.m))
                        Text("On your iPhone: Gym → Settings → Connect to your Mac → Scan the code.")
                            .font(.secondaryText).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("iPhone sync")
        } footer: {
            Text(server.enabled
                 ? "Your iPhone syncs with this Mac over Tailscale whenever both are on, wherever you are. Keep Gym open here (it can be in the background). Only your own devices on Tailscale can reach it, and only with the pairing code."
                 : "Log on your iPhone and see it here, and the other way round. This Mac keeps the main copy.")
        }
        .confirmationDialog("Make a new pairing code?", isPresented: $confirmNewCode) {
            Button("New code") { server.newCode() }
        } message: {
            Text("Your iPhone stops syncing until you connect it again with the new code.")
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; f.locale = appLocale
        return Date().timeIntervalSince(d) < 60 ? "Just now" : f.localizedString(for: d, relativeTo: Date())
    }

    private func qrImage(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: out.extent.width, height: out.extent.height))
    }
}
#endif

/// On the iPhone: connected or not, and what happened last.
struct MacSyncSection: View {
    @ObservedObject private var client = SyncClient.shared
    @State private var connecting = false
    @State private var confirmDisconnect = false

    var body: some View {
        Section {
            if client.connected {
                LabeledContent("Connected to", value: client.macName)
                LabeledContent("Last synced") {
                    if client.syncing { ProgressView() } else { Text(client.lastSync.map(relative) ?? "Not yet") }
                }
                let waiting = client.pendingCount()
                LabeledContent("Waiting to send") {
                    Text(waiting == 0 ? "Nothing" : "\(waiting) change\(waiting == 1 ? "" : "s")").monospacedDigit()
                        .foregroundStyle(waiting > 0 && client.error != nil ? palette.warn : .secondary)
                }
                if let e = client.error {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(palette.warn).font(.secondaryText)
                    Text("Changes stay safe on this phone and go across as soon as the Mac is reachable.").font(.note).foregroundStyle(.secondary)
                }
                Button("Sync now") { Task { await client.sync() } }.disabled(client.syncing)
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }
            } else {
                Button("Connect to your Mac…") { connecting = true }
            }
        } header: {
            Text("Mac sync")
        } footer: {
            Text(client.connected
                 ? "Syncs when you open Gym, shortly after each change and every minute, whenever your Mac is on with Gym open. Away from it, everything still works and syncs later."
                 : "Use Gym on your Mac too? Connect to keep both in step.")
        }
        .sheet(isPresented: $connecting) { ConnectMacView().appStyle() }
        .confirmationDialog("Stop syncing with \(client.macName)?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { client.disconnect() }
        } message: {
            Text("Your data stays on both devices; they just stop updating each other.")
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; f.locale = appLocale
        return Date().timeIntervalSince(d) < 60 ? "Just now" : f.localizedString(for: d, relativeTo: Date())
    }
}

/// Address and pairing code (typed or scanned from the Mac), then connect.
struct ConnectMacView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var found: SyncClient.Mac?
    @State private var confirmReplace = false
    @State private var scanning = false
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            Form {
                #if os(iOS)
                Section {
                    Button { scanning = true } label: { Label("Scan the code on your Mac", systemImage: "qrcode.viewfinder") }
                } footer: {
                    Text("On your Mac: Gym → Settings → iPhone sync. Turn it on and a code appears.")
                }
                #endif
                Section {
                    TextField("Mac address", text: $address, prompt: Text("your-mac.your-tailnet.ts.net"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                    TextField("Pairing code", text: $code, prompt: Text("ABCD-1234"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                } header: {
                    Text("Or type them")
                } footer: {
                    if let error { Text(error).foregroundStyle(palette.warn) }
                }
            }
            .themedForm()
            .navigationTitle("Connect to your Mac")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $scanning, onDismiss: {
                // Only once the camera has gone, or the confirmation can't appear.
                if scanned { scanned = false; check() }
            }) {
                BarcodeScanner(title: "Scan the code on your Mac", qr: true) { text in
                    if let p = SyncClient.parsePairing(text) { address = p.address; code = p.code; scanned = true }
                    else { error = "That isn't Gym's pairing code. It's under Gym → Settings → iPhone sync on your Mac." }
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Connect", action: check).disabled(address.isEmpty || code.isEmpty)
                    }
                }
            }
            .confirmationDialog("Replace this iPhone's data with \(found?.name ?? "your Mac")'s?", isPresented: $confirmReplace,
                                titleVisibility: .visible) {
                Button("Use the Mac's data", role: .destructive) { connect() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your Mac already has Gym data, so it replaces what's on this iPhone. After that, changes on either one go to the other.")
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func check() {
        working = true; error = nil
        Task {
            do {
                let mac = try await SyncClient.shared.check(address: address, code: code)
                found = mac
                if mac.hasData && ctx.hasSyncedData { working = false; confirmReplace = true } else { connect() }
            } catch {
                self.error = message(error); working = false
            }
        }
    }

    private func connect() {
        guard let mac = found else { return }
        working = true
        Task {
            do {
                SyncClient.shared.context = ctx
                try await SyncClient.shared.connect(address: address, code: code, mac: mac)
                dismiss()
            } catch {
                self.error = message(error)
            }
            working = false
        }
    }

    private func message(_ e: Error) -> String {
        if let s = e as? SyncClient.SyncError { return s.text }
        return "Couldn't reach your Mac at that address. Check that it's on, Gym is open with iPhone sync turned on, and Tailscale is connected on both."
    }
}
