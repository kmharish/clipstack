import Foundation
import CoreData

extension ClipItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClipItem> {
        return NSFetchRequest<ClipItem>(entityName: "ClipItem")
    }

    /// Unique identifier for this item.
    @NSManaged public var id: UUID?

    /// The raw string content that was copied.
    @NSManaged public var content: String?

    /// Semantic type: "text", "url", "rtf", or "file".
    @NSManaged public var contentType: String?

    /// When the item was copied.
    @NSManaged public var timestamp: Date?

    /// Position in the ordered stack (0 = most recent).
    @NSManaged public var sortOrder: Int32
}

// MARK: - Identifiable
extension ClipItem: Identifiable {}

// MARK: - Convenience
extension ClipItem {

    /// Content type constants.
    enum ContentType: String {
        case text = "text"
        case url  = "url"
        case rtf  = "rtf"
        case file = "file"
    }

    /// Returns a display-ready truncated string of the content.
    var displayContent: String {
        guard let content = content else { return "(empty)" }
        let maxLength = 60
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "…"
        }
        return content
    }

    /// SF Symbol name appropriate for the content type.
    var symbolName: String {
        switch ContentType(rawValue: contentType ?? "text") {
        case .url:  return "link"
        case .rtf:  return "doc.richtext"
        case .file: return "doc"
        default:    return "doc.text"
        }
    }
}
