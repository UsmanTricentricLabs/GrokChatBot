//
//  Persistence.swift
//  Grok
//
//  Created by Tricentric Labs on 01/10/2026.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: "Grok")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            guard let error = error as NSError? else { return }

            // A store the current model cannot open is a store from an older
            // build. History is a convenience, not something worth refusing to
            // launch over, so the file is replaced and the app starts clean.
            NSLog("Store could not be opened, starting fresh: \(error), \(error.userInfo)")
            if let url = description.url, !inMemory {
                try? FileManager.default.removeItem(at: url)
                container.loadPersistentStores { _, retryError in
                    if let retryError {
                        NSLog("Store is unusable: \(retryError.localizedDescription)")
                    }
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }
}
