import Foundation
import SwiftUI

/// Shorthand for `String(localized: …, bundle: .module)`. SwiftPM apps
/// don't automatically use the module's bundle for localized strings the
/// way Xcode app targets do; every literal needs `bundle: .module` to
/// reach the catalog at `Sources/NVMeterApp/Resources/Localizable.xcstrings`.
///
/// These wrappers are intentionally internal (not @inlinable / public)
/// because `Bundle.module` is itself internal — synthesized per-target.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Same idea for SwiftUI `Text` etc. that accept a `LocalizedStringResource`.
func LR(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
