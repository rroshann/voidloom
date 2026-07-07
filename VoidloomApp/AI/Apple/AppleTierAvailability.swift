import Foundation
import FoundationModels

/// Runtime capability probes for the Apple Intelligence tier. Kept in the app
/// target so Core stays free of FoundationModels imports.
enum AppleTierAvailability {
    static let preferAppleIntelligenceKey = "ai.preferAppleIntelligence"

    /// User-facing default override; `nil` in UserDefaults means ON (pending benchmark).
    static var preferAppleIntelligence: Bool {
        guard UserDefaults.standard.object(forKey: preferAppleIntelligenceKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: preferAppleIntelligenceKey)
    }

    static var foundationModelsAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return foundationModelsAvailableOnMacOS26
    }

    @available(macOS 26, *)
    private static var foundationModelsAvailableOnMacOS26: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
}
