import SwiftUI

/// Blocking screen when location is off: Drafft can't show people nearby without it.
/// No close button; it goes away by itself once location is back on.
struct LocationRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 72, height: 72)
                .background(DS.Palette.lime, in: .circle)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Turn location back on.")
                    .font(.display(40))
                    .displayLeading(40)
                    .foregroundStyle(DS.Palette.lime)
                    .accessibilityAddTraits(.isHeader)
                Text(branded: L("drafft needs it to show people near you. While Using the App is enough, and only your area is ever shown."), font: .body)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.drafftPrimary)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.night.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
