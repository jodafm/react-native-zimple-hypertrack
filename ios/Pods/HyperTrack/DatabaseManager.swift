import Foundation

protocol AbstractDatabaseManager: AnyObject {
  func getDatabaseManager(_ collectionType: EventCollectionType)
    -> EventsTableManager?
}

final class DatabaseManager {
  struct Input {
    let name: String
    let collectionTypes: [EventCollectionType]
  }

  private var instances: [EventCollectionType: EventsTableManager] = [:]
  private let dbManager: AbstractDatabase

  init(dbInput input: Input) {
    dbManager = GRDBQueue(dbPath: input.name)
    input.collectionTypes.forEach {
      switch $0 {
        case .online:
          instances[$0] = EventsTableManager(
            withInput: EventsTableManager.Input(
              tableName: Constant.Database.TableName.onlineEvent,
              dbManager: dbManager
            )
          )
        case .custom:
          instances[$0] = EventsTableManager(
            withInput: EventsTableManager.Input(
              tableName: Constant.Database.TableName.customEvent,
              dbManager: dbManager
            )
          )
      }
    }
  }
}

extension DatabaseManager: AbstractDatabaseManager {
  func getDatabaseManager(_ collectionType: EventCollectionType)
    -> EventsTableManager?
  { return instances[collectionType] }
}
