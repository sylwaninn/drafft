import SwiftUI

/// A field's label where the field is built by hand (sign-up's birthday, area, prompts): the same as
/// DrafftField's title.
struct FieldLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
    }
}
