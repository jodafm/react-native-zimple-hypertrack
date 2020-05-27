import Foundation
import GRDB
import UIKit

protocol AbstractDatabase: AnyObject {
  func createTable(_ sql: String) throws
  func insert(_ sql: String) throws
  func update(_ sql: String) throws
  func delete(_ sql: String) throws
  func transaction(_ sqls: [String]) throws
  func select<T: RowInitializable>(_ sql: String) throws -> [T]
}

final class MasterModel {
  static var name: String?

  static let sharedQueue: DatabaseQueue = {
    let documentsDirectory = (
      NSSearchPathForDirectoriesInDomains(
        .documentDirectory,
        .userDomainMask,
        true
      )[0] as NSString
    ) as String
    let name = MasterModel.name ?? Constant.Database.name
    let pathToDatabase = documentsDirectory.appending("/\(name)")
    var config = GRDB.Configuration()
    config.defaultTransactionKind = .deferred
    let fileManager = FileManager.default
    do {
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.none],
        ofItemAtPath: pathToDatabase
      )
    } catch {}
    return try! DatabaseQueue(path: pathToDatabase, configuration: config)
  }()
}

final class GRDBQueue: AbstractDatabase {
  init(dbPath: String) {
    MasterModel.name = dbPath
    MasterModel.sharedQueue.setupMemoryManagement(in: UIApplication.shared)
  }

  func createTable(_ sql: String) throws { try executeWrite(sql) }

  func insert(_ sql: String) throws { try executeWrite(sql) }

  func update(_ sql: String) throws { try executeWrite(sql) }

  func delete(_ sql: String) throws { try executeWrite(sql) }

  func transaction(_ sqls: [String]) throws {
    do {
      try MasterModel.sharedQueue.inTransaction { dataBase in
        try sqls.forEach { try dataBase.execute(sql: $0) }
        return .commit
      }
    } catch let error as DatabaseError {
      logDatabase.error(
        "Failed to perform transactions for SQLs: \(sqls) with error: \(error)"
      )
    }
  }

  func select<T: RowInitializable>(_ sql: String) throws -> [T] {
    return try executeRead(sql)
  }

  private func executeWrite(_ sql: String) throws {
    do {
      try MasterModel.sharedQueue.write { (dataBase) -> Void in
        try dataBase.execute(sql: sql)
      }
    } catch let error as DatabaseError {
      logDatabase.error(
        "Failed to execute write for SQL: \(sql) with error: \(error)"
      )
    }
  }

  private func executeRead<T: RowInitializable>(_ sql: String) throws -> [T] {
    do {
      return try MasterModel.sharedQueue.read { dataBase in
        try Row.fetchAll(dataBase, sql: sql)
      }.compactMap { T(row: $0) }
    } catch let error as DatabaseError {
      logDatabase.error(
        "Failed to execute read for SQL: \(sql) with error: \(error)"
      )
      return []
    }
  }
}

final class GRDBPool: AbstractDatabase {
  private let pool: DatabasePool

  init(dbPath: String) throws {
    var config = GRDB.Configuration()
    config.maximumReaderCount = 1
    pool = try DatabasePool(path: dbPath, configuration: config)
  }

  func createTable(_ sql: String) throws { try executeWrite(sql) }

  func insert(_ sql: String) throws { try executeWrite(sql) }

  func update(_ sql: String) throws { try executeWrite(sql) }

  func delete(_ sql: String) throws { try executeWrite(sql) }

  func transaction(_ sqls: [String]) throws {
    try pool.writeInTransaction { dataBase in
      try sqls.forEach { try dataBase.execute(sql: $0) }
      return .commit
    }
  }

  func select<T: RowInitializable>(_ sql: String) throws -> [T] {
    return try executeRead(sql)
  }

  private func executeWrite(_ sql: String) throws {
    try pool.write { (dataBase) -> Void in try dataBase.execute(sql: sql) }
  }

  private func executeRead<T: RowInitializable>(_ sql: String) throws -> [T] {
    return try pool.read { dataBase in try Row.fetchAll(dataBase, sql: sql) }
      .compactMap { T(row: $0) }
  }
}
