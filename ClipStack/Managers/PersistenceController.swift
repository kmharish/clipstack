import CoreData
import os.log

/// Manages the Core Data stack for ClipStack.
///
/// Use `PersistenceController.shared` throughout the app.
/// An in-memory store variant is provided for unit tests via `PersistenceController(inMemory: true)`.
final class PersistenceController {

    // MARK: - Shared Instance

    static let shared = PersistenceController()

    // MARK: - Core Data Stack

    let container: NSPersistentContainer

    private let logger = Logger(subsystem: "com.clipstack.ClipStack", category: "Persistence")

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ClipStack")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this gracefully rather than crashing.
                self?.logger.error("Core Data failed to load store: \(error), \(error.userInfo)")
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            }
            self?.logger.debug("Loaded persistent store: \(storeDescription)")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Context Access

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// Creates a new background context for off-main-thread operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    // MARK: - Save

    /// Saves the view context if there are unsaved changes.
    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            logger.error("Failed to save Core Data context: \(nsError), \(nsError.userInfo)")
        }
    }

    // MARK: - Fetch

    /// Fetches all `ClipItem` entities ordered by `sortOrder` ascending.
    func fetchAllItems() -> [ClipItem] {
        let request = ClipItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            logger.error("Failed to fetch ClipItems: \(error)")
            return []
        }
    }

    // MARK: - Delete

    /// Deletes all `ClipItem` records from the store.
    func deleteAllItems() {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = ClipItem.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        do {
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        } catch {
            logger.error("Failed to delete all ClipItems: \(error)")
        }
    }

    // MARK: - Insert

    /// Creates and inserts a new `ClipItem` with the given parameters.
    @discardableResult
    func insertItem(content: String, contentType: String, sortOrder: Int32) -> ClipItem {
        let item = ClipItem(context: viewContext)
        item.id = UUID()
        item.content = content
        item.contentType = contentType
        item.sortOrder = sortOrder
        item.timestamp = Date()
        return item
    }
}
