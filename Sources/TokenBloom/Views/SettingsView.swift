import AppKit
import SwiftUI

struct SettingsView: View {
    let store: QuotaStore
    let language: LanguageSettings
    @State private var loginItem = LoginItemManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section(language.text("settings.general")) {
                Picker(
                    language.text("settings.language"),
                    selection: Binding(
                        get: { language.language },
                        set: { language.language = $0 }
                    )
                ) {
                    Text(language.text("settings.chinese")).tag(AppLanguage.simplifiedChinese)
                    Text(language.text("settings.english")).tag(AppLanguage.english)
                }
                .pickerStyle(.segmented)

                Toggle(isOn: Binding(
                    get: { loginItem.isRegistered },
                    set: { loginItem.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("settings.launchAtLogin"))
                        Text(language.text("settings.launchAtLogin.detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(language.text("settings.systemStatus"), value: loginItem.statusText(language: language))

                if loginItem.requiresApproval {
                    HStack(spacing: 10) {
                        Label(language.text("settings.approvalRequired"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(language.text("settings.openLoginItems")) { loginItem.openSystemSettings() }
                    }
                    .font(.caption)
                }

                if let errorMessage = loginItem.errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(language.text("settings.data")) {
                ForEach(Array(store.codexHomes.enumerated()), id: \.offset) { index, home in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Codex \(index + 1)")
                            Text(home.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(language.text("settings.chooseFolder")) {
                            chooseCodexHome(for: index)
                        }
                    }
                }
                LabeledContent(language.text("settings.refreshRate"), value: language.text("settings.refreshRate.value"))
                Text(language.text("settings.privacy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 420)
        .onAppear { loginItem.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loginItem.refresh() }
        }
    }

    private func chooseCodexHome(for index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = language.text("settings.chooseFolder")
        if panel.runModal() == .OK, let url = panel.url {
            store.setCodexHome(url, for: index)
        }
    }
}
