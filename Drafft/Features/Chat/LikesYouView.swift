import SwiftUI

/// drafft tempo: everyone who already liked you, as the Likes mosaic (`LikesMosaic`). Like back and
/// it's mutual right away.
struct LikesYouView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var open: Profile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    if app.likedMe.isEmpty {
                        TempoLikesLead()
                        Text("No new likes right now. Keep swiping, they'll show up here.")
                            .font(.body)
                            .foregroundStyle(DS.Palette.body)
                            .padding(DS.Space.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                    } else {
                        LikesMosaic(items: app.likedMe, visitKey: "likes-sheet") {
                            TempoLikesLead()
                        } tile: { p, height in
                            LikeTile(profile: p, height: height) {
                                Haptics.tap()
                                open = p
                            } onLike: {
                                app.swipe(p, liked: true)
                            }
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
                    Button("Close", image: .icon("close")) { dismiss() }
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
}
