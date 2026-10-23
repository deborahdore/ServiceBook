import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.notificationsKey) private var notifications = false
    @AppStorage(AppSettings.connectionOKKey) private var connectionOK = false
    @AppStorage(AppSettings.modelKey) private var model = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: Binding(get: { AppLanguage.selected }, set: { AppLanguage.select($0) })) {
                        ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                } footer: {
                    Text("Photos, the document scanner and other system screens switch language the next time you open the app.")
                }

                Section {
                    NavigationLink {
                        AIConnectionView()
                    } label: {
                        LabeledContent {
                            Text(!AppSettings.hasKey ? "Not set up" : (connectionOK ? "Connected" : "Not tested"))
                                .foregroundStyle(AppSettings.hasKey && connectionOK ? Color.green : Color.secondary)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Claude connection")
                                    Text(model.isEmpty ? AppSettings.defaultModel : model)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "sparkles")
                            }
                        }
                    }
                } header: {
                    Text("AI manual import")
                } footer: {
                    Text("Optional. Used only to find or read owner's manuals. Vehicle details and manual text are sent to Anthropic when you run an import; your service history never leaves the device.")
                }

                Section {
                    Toggle("Date reminders", isOn: $notifications)
                } footer: {
                    Text("A notification one week before and on the day a time-based item is due. Mileage-based items are shown in the app — keep your mileage up to date.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/deborahdore/vehicle-maintenance")!)
                    Text("Schedules are a guide. Always follow your owner's manual and your mechanic's advice — the authors accept no responsibility for missed or incorrect maintenance.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: notifications) { _, on in
                Task { @MainActor in
                    if on, !(await ReminderScheduler.requestPermission()) { notifications = false }
                    ReminderScheduler.reschedule(context: context)
                }
            }
        }
    }
}
