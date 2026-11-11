import SwiftUI

struct ContentView: View {
    @StateObject private var session = LockSession()
    @State private var key: String = KeychainStore.load("activationKey") ?? AppConfig.defaultKey
    @State private var showKey = false
    @Environment(\.scenePhase) private var scenePhase

    /// 打开 App 就自动开锁
    @AppStorage("autoUnlockOnOpen") private var autoUnlockOnOpen = true
    @State private var backgroundedAt: Date?
    @State private var lastAutoUnlock = Date.distantPast

    private var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(AppConfig.doorName).font(.title2).bold()
                Text([AppConfig.roomLabel, AppConfig.doorMac].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            Text(session.statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)

            Button {
                trigger(manual: true)
            } label: {
                Text(session.busy ? "开锁中…" : "开 锁")
                    .font(.system(size: 38, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                    .background(session.busy ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(26)
            }
            .disabled(session.busy)
            .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button("查电量") { session.battery(key: normalizedKey) }
                Button("钥匙") { showKey = true }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)

            Spacer(minLength: 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.logLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 170)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showKey) {
            KeySheet(key: $key, autoUnlock: $autoUnlockOnOpen)
        }
        .onAppear { autoUnlockIfNeeded(reason: "启动") }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
                backgroundedAt = nil
                if away > 1.5 { autoUnlockIfNeeded(reason: "回到前台") }
            default:
                break
            }
        }
    }

    // MARK: - 触发

    private func trigger(manual: Bool) {
        let k = normalizedKey
        guard k.count == 32 else {
            showKey = true
            return
        }
        KeychainStore.save(k, "activationKey")
        if manual { lastAutoUnlock = Date() }
        session.unlock(key: k)
    }

    private func autoUnlockIfNeeded(reason: String) {
        guard autoUnlockOnOpen, !session.busy else { return }
        guard normalizedKey.count == 32 else { return }
        guard Date().timeIntervalSince(lastAutoUnlock) > 5 else { return }
        lastAutoUnlock = Date()
        KeychainStore.save(normalizedKey, "activationKey")
        session.unlock(key: normalizedKey)
    }
}

struct KeySheet: View {
    @Binding var key: String
    @Binding var autoUnlock: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("开锁钥匙（32 位十六进制）")) {
                    TextField("activationKey", text: $key)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(.footnote, design: .monospaced))
                }
                Section {
                    Toggle("打开 App 就自动开锁", isOn: $autoUnlock)
                } footer: {
                    Text("从后台切回来也会自动开一次。关掉后只能点按钮。")
                }
                Section {
                    Text("钥匙只保存在本机 Keychain，不会上传。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("钥匙")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), "activationKey")
                        dismiss()
                    }
                }
            }
        }
    }
}
