import SwiftUI

/// Settings › Notifications: the system permission first, then what to be notified about.
struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var notifications = NotificationService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    statusBlock
                    group(L("Activity")) {
                        toggle(L("New matches"), "heart", $notifications.matches)
                        divider
                        toggle(L("Likes you"), "user-heart", $notifications.likes)
                        divider
                        toggle(L("Messages"), "chat-round-line", $notifications.messages)
                        divider
                        toggle(L("Show message previews"), "chat-square-line", $notifications.messagePreviews,
                               detail: L("Off: notifications only say who wrote, not what."))
                            .disabled(!notifications.messages)
                            .opacity(notifications.messages ? 1 : 0.45)
                        divider
                        toggle(L("Reactions"), "smile-circle", $notifications.reactions,
                               detail: L("When someone reacts to one of your messages."))
                            .disabled(!notifications.messages)
                            .opacity(notifications.messages ? 1 : 0.45)
                    }
                    group(L("Sessions")) {
                        toggle(L("The evening before"), "moon", $notifications.sessionEvening,
                               detail: L("At \(eveningTime), a reminder of tomorrow's session."))
                        divider
                        toggle(L("An hour before"), "alarm", $notifications.sessionHourBefore)
                    }
                    // The weekly boost comes with drafft tempo: its notification only makes sense then.
                    if app.isPremium {
                        group(Brand.tierName) {
                            toggle(L("Weekly boost"), "bolt", $notifications.weeklyBoost,
                                   detail: L("When your free boost of the week is added."))
                        }
                    }
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) { dismiss() }
                }
            }
        }
        .trackScreen(.notificationSettings)
    }

    @ViewBuilder
    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Image(notifications.isAllowed ? "bell-ring" : "bell-off")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(notifications.isAllowed ? DS.Palette.onAccentOnNight : .white)
                    .frame(width: 48, height: 48)
                    .background(notifications.isAllowed ? DS.Palette.accentOnNight : .white.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notifications.isAllowed ? "Notifications are on" : "Notifications are off")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(notifications.isAllowed ? "Choose what you hear about below."
                         : notifications.isDenied ? "Turn them on in iPhone Settings to hear about matches and sessions."
                         : "Hear about matches, messages and sessions right away.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if notifications.permission != .allowed {
                PermissionButton(permission: notifications, askTitle: "Turn on notifications", symbol: "bell")
                    .buttonStyle(.drafftPrimary)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBlock()
    }

    /// The section title lives inside its white block (no loose text on the sage page).
    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(branded: title, font: .footnote.weight(.bold), brandWeight: .heavy)
                .foregroundStyle(DS.Palette.mute)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.bottom, DS.Space.xs)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        .disabled(!notifications.isAllowed)
        .opacity(notifications.isAllowed ? 1 : 0.5)
    }

    private var divider: some View { Divider().padding(.leading, 60) }

    /// When the evening-before reminder goes out (20:00), in the app's time format.
    private var eveningTime: String {
        let d = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now
        return d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
    }

    private func toggle(_ title: String, _ icon: String, _ isOn: Binding<Bool>, detail: String? = nil) -> some View {
        Toggle(isOn: isOn.animation(Motion.snappy)) {
            HStack(spacing: DS.Space.md) {
                Image(icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(DS.Palette.canvasSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(DS.Palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(DS.Palette.lime)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }
}
