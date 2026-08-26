import Foundation
import SwiftUI

/// The bundle that holds our compiled localizations.
///
/// SwiftPM's synthesized `Bundle.module` accessor only checks two places:
///   1. `Bundle.main.bundleURL/NVMeter_NVMeterApp.bundle` — the bundle root
///      of the .app, where codesign forbids loose items, and
///   2. the absolute `.build/…` path on the dev machine.
/// Neither works for a distributed .app, so v0.1.1 shipped with strings
/// resolving only on the development Mac (and would have crashed on
/// machines where neither path exists).
///
/// `localizationBundle` checks `Contents/Resources/` FIRST — where
/// `scripts/build-app.sh` now copies the resource bundle — then falls
/// back to `Bundle.module` for `swift run` development builds.
let localizationBundle: Bundle = {
    if let resourceURL = Bundle.main.resourceURL {
        let packaged = resourceURL.appendingPathComponent("NVMeter_NVMeterApp.bundle")
        if let bundle = Bundle(url: packaged) {
            return bundle
        }
    }
    return Bundle.module
}()

/// Shorthand for `String(localized: …)` resolved against our bundle.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: localizationBundle)
}

/// Same idea for SwiftUI controls. Returning the already-resolved `String`
/// keeps the call sites compatible with Xcode 15's `StringProtocol`-based
/// control initializers while still using NVMeter's packaged bundle.
func LR(_ key: String.LocalizationValue) -> String {
    L(key)
}
