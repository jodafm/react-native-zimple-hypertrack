import Foundation

enum DataBaseResult<Model> {
  case success(Model)
  case failure(String)
}

protocol AbstractDatabaseInfo { func tableName() -> String }

protocol AbstractDatabaseProtocol {
  associatedtype T
  func insert(items: [T], result: @escaping (DataBaseResult<[T]>) -> Void)
  func delete(items: [T], result: @escaping (DataBaseResult<[T]>) -> Void)
  func fetch(count: UInt, result: @escaping (DataBaseResult<[T]>) -> Void)
  func sortedFetch(count: UInt, result: @escaping (DataBaseResult<[T]>) -> Void)
  func deleteAll(result: @escaping (_ status: Bool) -> Void)
}
