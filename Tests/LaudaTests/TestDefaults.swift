import Foundation

/// Preferences that live only in memory, for tests that store something.
///
/// A named suite would do as well, except that a domain is a file in
/// ~/Library/Preferences: removing the domain empties it, but the file
/// stays, and a fresh name per run leaves one behind every time (there were
/// 588 of them before this). Nothing here touches the disk.
///
/// Reads fall back to the registration domain alone, so `registerDefaults`
/// still answers, while values written anywhere else — including whatever a
/// previous run may have left in the test runner's own domain — stay out.
final class TestDefaults: UserDefaults {
    private var stored: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        stored[key] ?? volatileDomain(forName: UserDefaults.registrationDomain)[key]
    }

    override func set(_ value: Any?, forKey key: String) { stored[key] = value }
    override func set(_ value: Int, forKey key: String) { stored[key] = value }
    override func set(_ value: Double, forKey key: String) { stored[key] = value }
    override func set(_ value: Float, forKey key: String) { stored[key] = value }
    override func set(_ value: Bool, forKey key: String) { stored[key] = value }
    override func set(_ url: URL?, forKey key: String) { stored[key] = url }
    override func removeObject(forKey key: String) { stored[key] = nil }

    override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
}
