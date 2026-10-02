import Foundation

// Bundle.main selects the user's preferred supported language, falling back to English.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, value: key, comment: "")
}
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}
