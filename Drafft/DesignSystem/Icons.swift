import SwiftUI

/// App icons live in Resources/Assets.xcassets/Icons as custom symbols (Solar linear set, plus
/// Material Symbols for the sports it lacks), so `Image(name)` and `Label(_:image:)` size with the
/// font like SF Symbols did. APIs that only take a resource (`Button`, `Menu`) go through `.icon`.
extension ImageResource {
    static func icon(_ name: String) -> ImageResource { ImageResource(name: name, bundle: .main) }
}
