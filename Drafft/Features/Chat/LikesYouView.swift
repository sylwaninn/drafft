import SwiftUI

/// drafft tempo: everyone who already liked you. Like back and it's a match right away.
struct LikesYouView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var open: Profile?

    private let columns = [GridItem(.flexible(), spacing: DS.Space.sm), GridItem(.flexible(), spacing: DS.Space.sm)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("They like you.")
                            .font(.display(34))
                            .foregroundStyle(DS.Palette.accentOnNight)
                            .accessibilityAddTraits(.isHeader)
                        Text("Like back and it's a match straight away.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(DS.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nightBlock()

                    if app.likedMe.isEmpty {
                        Text("No new likes right now. Keep swiping, they'll show up here.")
                            .font(.body)
                            .foregroundStyle(DS.Palette.body)
                            .padding(DS.Space.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                    }

                    LazyVGrid(columns: columns, spacing: DS.Space.sm) {
                        ForEach(app.likedMe) { p in
                            Button { open = p } label: { card(p) }
                                .buttonStyle(PressScaleStyle(scale: 0.97))
                                .accessibilityLabel("\(p.name), \(p.age). Open profile")
                        }
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            // Same presentation and actions as a profile opened from Discover.
            .sheet(item: $open) { p in
                Group {
                    NavigationStack {
                        ProfileDetailView(profile: p, mode: .discover) { liked, opener in
                            open = nil
                            app.swipe(p, liked: liked, opener: opener)
                        } onSuperLike: { opener in
                            open = nil
                            app.swipe(p, liked: true, superLike: true, opener: opener)
                        }
                    }
                }
                .sheetSurface()
            }
        }
    }

    private func card(_ p: Profile) -> some View {
        Photo(name: p.portrait, side: 180)
            .frame(height: 230)
            .overlay {
                // design-lint: allow gradient - photo scrim under the name
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: DS.Palette.night.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                ProfileIdentity(profile: p, nameSize: 22, showsLocation: false, showsSuperLike: true)
                    .padding(DS.Space.md)
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
    }
}
