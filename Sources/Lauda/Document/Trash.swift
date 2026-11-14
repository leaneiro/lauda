import Foundation

/// Where files go on their way out. A document follows its file wherever
/// it moves, the Trash included; this tells the Trash from everywhere else.
enum Trash {
    /// Whether `url` is in a Trash: the home folder's, or the one another
    /// volume keeps at its root (.Trashes), which is also where the system
    /// puts a file trashed from that volume.
    static func contains(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var relationship = FileManager.URLRelationship.other
        if (try? fileManager.getRelationship(
            &relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: url
        )) != nil, relationship == .contains {
            return true
        }
        return url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
