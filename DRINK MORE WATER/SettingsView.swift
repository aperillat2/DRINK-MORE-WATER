import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @Binding var startHour: Int
    @Binding var endHour: Int
    @Binding var intervalMinutes: Int
    @Binding var selectedSound: String
    @Binding var muteTapSound: Bool
    @Binding var muteNotifications: Bool
    @Binding var volumeUnit: VolumeUnit
    /// True when the user has turned notifications off for this app in iOS Settings.
    var notificationsDenied: Bool = false
    var onApply: () -> Void
    /// Called after the user confirms the reset.
    var onResetToday: () -> Void
    var onShowHelp: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The confirmation is presented from this sheet: on iOS 17 an alert attached to the
    /// view underneath an open sheet never appears.
    @State private var showResetConfirmation = false
    @AppStorage(HealthSync.Keys.enabled, store: SharedStore.defaults) private var saveToHealth = false
    /// True when access is turned off in the Health app, so saving can't work.
    @State private var healthDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    LabeledContent("Units") {
                        Picker("Units", selection: $volumeUnit) {
                            // Spoken in full; VoiceOver may otherwise spell out "oz"/"ml".
                            Text("oz").tag(VolumeUnit.oz)
                                .accessibilityLabel(VolumeUnit.oz.spokenName)
                            Text("ml").tag(VolumeUnit.ml)
                                .accessibilityLabel(VolumeUnit.ml.spokenName)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityIdentifier("volumeUnitPicker")
                    }
                    Toggle("Mute Add Water Sound", isOn: $muteTapSound)
                }

                if HealthSync.isAvailable {
                    Section {
                        Toggle("Save to Apple Health", isOn: saveToHealthBinding)
                            .accessibilityIdentifier("saveToHealthToggle")
                    } footer: {
                        if healthDenied {
                            Text("Access is turned off. You can allow it in the Health app: tap your profile picture, then Apps.")
                        } else {
                            Text("Each drink you add is also saved in the Health app.")
                        }
                    }
                }

                Section(
                    header: Text("Reminders"),
                    footer: Text("Reminders only occur between the start and end hours.")
                ) {
                    if notificationsDenied {
                        notificationsDeniedRow
                    }
                    Toggle("Mute Notifications", isOn: $muteNotifications)
                    Picker("Start", selection: $startHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    // End can't be before Start (the window doesn't wrap past midnight),
                    // so only offer hours from Start onward.
                    Picker("End", selection: $endHour) {
                        ForEach(startHour..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    Picker("Frequency", selection: $intervalMinutes) {
                        ForEach(reminderChoices, id: \.self) { value in
                            Text(intervalLabel(value)).tag(value)
                        }
                    }
                    Picker("Sound", selection: $selectedSound) {
                        // Explicit none option (empty string means no sound)
                        Text("None").tag("")
                        ForEach(availableSoundsBaseNames(), id: \.self) { name in
                            Text(Self.soundDisplayName(name)).tag(name)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Text("Reset today's intake")
                    }
                } footer: {
                    HStack {
                        Text("App Version \(versionLabel)")
                        Spacer()
                        Button {
                            dismiss()
                            // Start the walkthrough after the sheet has begun dismissing.
                            Task { onShowHelp() }
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                        .textCase(nil)
                    }
                    .padding(.top, 8)
                }
            }
            .listSectionSpacing(.compact)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { healthDenied = HealthSync.isSharingDenied }
        .onChange(of: startHour) { _, newStart in
            // Keep the window valid if Start moves past End.
            if endHour < newStart { endHour = newStart }
        }
        .alert("Reset today's intake?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { onResetToday() }
        } message: {
            Text("This will set today's filled amount back to 0 \(volumeUnit.label).")
        }
        .dynamicTypeSize(.large ... .accessibility1)
    }

    /// Turning it on asks for Health permission (iOS only shows the sheet the first time).
    /// Turning it off stops saving; drinks already in Health stay there.
    private var saveToHealthBinding: Binding<Bool> {
        Binding(
            get: { saveToHealth },
            set: { isOn in
                saveToHealth = isOn
                guard isOn else {
                    HealthSync.clearPending()
                    return
                }
                Task {
                    let allowed = await HealthSync.requestAuthorization()
                    // Declined (now or earlier): switch back off; the footer says where to allow it.
                    healthDenied = HealthSync.isSharingDenied
                    if allowed {
                        await HealthSync.savePending()
                    } else {
                        saveToHealth = false
                    }
                }
            }
        )
    }

    private var notificationsDeniedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notifications are turned off for this app.", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        }
    }

    /// Hour in the user's preferred style, e.g. "7 AM" or "07" for 24-hour locales.
    private func hourLabel(_ hour24: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour24, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    private let oncePerDaySentinel = 0

    private var reminderChoices: [Int] {
        var base = [oncePerDaySentinel, 15, 30, 45, 60, 90, 120]
        if !base.contains(intervalMinutes) {
            base.append(intervalMinutes)
        }
        return base.sorted()
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes == oncePerDaySentinel {
            return String(localized: "Once a day")
        }
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? String(localized: "Every hour") : String(localized: "Every \(hours) hours")
        }
        return String(localized: "Every \(minutes) minutes")
    }

    /// Name shown for a sound file. The stored value stays the file name; only the label is translated.
    static func soundDisplayName(_ fileName: String) -> String {
        switch fileName {
        case "drink more water": return String(localized: "drink more water", comment: "Reminder sound name")
        case "water pour 1": return String(localized: "water pour 1", comment: "Reminder sound name")
        case "water pour 2": return String(localized: "water pour 2", comment: "Reminder sound name")
        default: return fileName
        }
    }

    private func availableSoundsBaseNames() -> [String] {
        var set = Set<String>()
        let fm = FileManager.default
        func add(from path: String) {
            if let items = try? fm.contentsOfDirectory(atPath: path) {
                for item in items where item.lowercased().hasSuffix(".caf") || item.lowercased().hasSuffix(".aiff") || item.lowercased().hasSuffix(".wav") {
                    let base = (item as NSString).deletingPathExtension
                    set.insert(base)
                }
            }
        }
        if let base = Bundle.main.resourcePath {
            add(from: base)
            let soundsPath = (base as NSString).appendingPathComponent("Sounds")
            add(from: soundsPath)
        }
        if set.isEmpty { set.insert("drink more water") }
        return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (v?, b?):
            return "\(v) (\(b))"
        case let (v?, nil):
            return v
        case let (nil, b?):
            return b
        default:
            return String(localized: "Unknown")
        }
    }
}

#Preview {
    NotificationSettingsView(
        startHour: .constant(7), endHour: .constant(20), intervalMinutes: .constant(60),
        selectedSound: .constant("drink more water"), muteTapSound: .constant(false),
        muteNotifications: .constant(false), volumeUnit: .constant(.oz),
        notificationsDenied: true,
        onApply: {}, onResetToday: {}, onShowHelp: {}
    )
}
