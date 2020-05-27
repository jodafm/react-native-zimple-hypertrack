import Foundation
import GRDB

enum JSONResult {
  case success([String: Any])
  case failure(String)
}

protocol JSONDictProtocol { func jsonDict() -> JSONResult }

protocol RowInitializable { init?(row: Row) }

struct Event: JSONDictProtocol {
  let type: EventType
  let sortedKey: String
  let data: String
  let id: String
  let recordedAt: String

  func jsonDict() -> JSONResult {
    var dict: [String: Any] = [:]
    if let jsonData = data.data(using: .utf8) {
      do {
        if let jsonDict = try JSONSerialization.jsonObject(with: jsonData)
          as? [String: Any]
        { dict[Constant.ServerKeys.Event.data] = jsonDict } else {
          return JSONResult.failure("Bad Json")
        }
      } catch let error as NSError {
        return JSONResult.failure(error.localizedDescription)
      }
    } else { return JSONResult.failure("Cannot create data") }
    dict[Constant.ServerKeys.Event.id] = id
    if type != EventType.checkIn {
      dict[Constant.ServerKeys.Event.type] = type.rawValue
    }
    dict[Constant.ServerKeys.Event.recordedAt] = recordedAt
    return JSONResult.success(dict)
  }
}

extension Event: RowInitializable {
  init?(row: Row) {
    guard let type = EventType(rawValue: row["type"] as? String ?? ""),
      let data = row["data"] as? String, let id = row["id"] as? String,
      let recordedAt = row["recorded_at"] as? String,
      let sortedKey = row["sortedKey"] as? String
      else { return nil }
    self.type = type
    self.data = data
    self.id = id
    self.recordedAt = recordedAt
    self.sortedKey = sortedKey
  }
}
