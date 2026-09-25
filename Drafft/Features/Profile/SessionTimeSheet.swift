import SwiftUI

/// Native date and time pickers in their own sheet: the system calendar for the day, the system
/// wheel for the time (5-minute steps). The time only joins the invite on "Add".
struct SessionTimeSheet: View {
    let isNew: Bool
    let taken: [Date]
    let onSave: (Date) -> Void
    var onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: Date?, taken: [Date], onSave: @escaping (Date) -> Void, onRemove: (() -> Void)? = nil) {
        isNew = initial == nil
        self.taken = taken
        self.onSave = onSave
        self.onRemove = onRemove
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        _date = State(initialValue: initial ?? cal.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrow) ?? tomorrow)
        UIDatePicker.appearance().minuteInterval = 5
    }

    private var isTaken: Bool { taken.contains { abs($0.timeIntervalSince(date)) < 60 } }
    private var isPast: Bool { date < .now }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    DatePicker("Day", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(DS.Palette.accentInk)
                        .padding(DS.Space.sm)
                        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

                    HStack {
                        Label("Time", systemImage: "clock.fill")
                            .font(.headline)
                            .foregroundStyle(DS.Palette.ink)
                        Spacer()
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .frame(minHeight: 60)
                    .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

                    if let onRemove {
                        Button(role: .destructive) {
                            Haptics.tap()
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove this time", systemImage: "trash")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DS.Palette.negative)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                        }
                    }
                }
                .padding(DS.Space.lg)
                .onChange(of: date) { Haptics.select() }
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .bottomBar {
                VStack(spacing: DS.Space.xs) {
                    Button {
                        Haptics.success()
                        onSave(date)
                        dismiss()
                    } label: {
                        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))
                        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(.app))
                        Text(isNew ? "Add \(day) at \(time)" : "Save \(day) at \(time)")
                            .rollingDigits(wording: day.wording)
                    }
                    .buttonStyle(.drafftPrimary)
                    .disabled(isTaken || isPast)
                    // Keeps its height when empty, so the button never moves.
                    Text(isTaken ? "You already offer this time." : (isPast ? "This time has passed." : " "))
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.negative)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.sm)
            }
            .navigationTitle(isNew ? "New time" : "Change time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
