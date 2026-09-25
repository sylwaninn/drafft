import SwiftUI

/// You › Language: the same list as at sign-up.
struct LanguageSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Drawn first, so the row reacts at once; the whole app then redraws in the new language.
    @State private var selection: AppLanguage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { i, l in
                        if i > 0 { Divider().padding(.leading, DS.Space.lg) }
                        let on = (selection ?? app.language) == l
                        Button {
                            Haptics.select()
                            selection = l
                            DispatchQueue.main.async { app.language = l }
                        } label: {
                            HStack {
                                Text(l.name).font(.body.weight(.medium)).foregroundStyle(DS.Palette.ink)
                                Spacer()
                                CheckDisc(isOn: on)
                            }
                            .padding(.horizontal, DS.Space.lg)
                            .frame(minHeight: 52)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                .padding(DS.Space.lg)
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
