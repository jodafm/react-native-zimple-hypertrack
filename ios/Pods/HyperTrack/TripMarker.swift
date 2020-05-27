import Foundation

struct TripMarker: AbstractServiceData {
  fileprivate let tripMarkerId: String
  fileprivate let recordedAt: Date
  fileprivate let dict: [String: Any]?

  init(withDict dict: [String: Any]?) {
    tripMarkerId = UUID().uuidString
    recordedAt = Date()
    self.dict = dict
  }

  func getType() -> EventType { return EventType.checkIn }

  func getSortedKey() -> String { return "" }

  func getId() -> String { return tripMarkerId }

  func getRecordedAt() -> Date { return recordedAt }

  func getJSONdata() -> String {
    guard let dict = self.dict else { return "" }
    do {
      return try String(
        data: JSONSerialization.data(withJSONObject: dict, options: []),
        encoding: .utf8
      ) ?? ""
    } catch {
      logGeneral.error(
        "Failed to serialize CheckInData to JSON from dict: \(dict as AnyObject) with error: \(error)"
      )
      return ""
    }
  }
}
