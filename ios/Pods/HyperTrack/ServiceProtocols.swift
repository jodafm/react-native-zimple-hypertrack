import Foundation

enum ServiceError: Error {
  case hardwareNotSupported
  case permissionNotTaken
  case userDenied
  case osDenied
  case unknown
}

protocol AbstractServiceData {
  func getId() -> String
  func getType() -> EventType
  func getRecordedAt() -> Date
  func getJSONdata() -> String
  func getSortedKey() -> String
}

protocol AbstractCollectionPipeline: AnyObject {
  func sendEvents<T: AbstractServiceData>(events: [T])
  func sendEvents<T: AbstractServiceData>(
    events: [T],
    eventCollectedIn collectionType: EventCollectionType
  )
  func tripMarkerEvent(_ metaData: [String: Any])
}

protocol AbstractService: AnyObject {
  var collectionProtocol: AbstractCollectionPipeline? { get set }

  var eventBus: AbstractEventBus? { get set }

  func setEventUpdatesDelegate(_ delegate: EventUpdatesDelegate?)
  func startService() throws -> ServiceError?
  func stopService()
  func isServiceRunning() -> Bool
  func isAuthorized() -> Bool
  func checkPermissionStatus()
}

extension AbstractService {
  func setEventUpdatesDelegate(_: EventUpdatesDelegate?) {}
}
