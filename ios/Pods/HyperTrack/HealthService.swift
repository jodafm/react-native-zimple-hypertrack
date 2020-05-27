import Foundation

protocol AbstractHealthBroadcastsReceiver {
  var updatesDelegate: HealthBroadcastsReceiverDelegate? { get set }
  func beginObserving()
  func endObserving()
}

final class HealthService: AbstractService {
  fileprivate var healthBroadcastsReceiver: AbstractHealthBroadcastsReceiver
  fileprivate var isRunning: Bool = false
  fileprivate weak var dataStore: AbstractReadWriteDataStore?
  weak var collectionProtocol: AbstractCollectionPipeline?
  weak var eventBus: AbstractEventBus?

  init(
    withCollectionProtocol collectionProtocol: AbstractCollectionPipeline?,
    eventBus: AbstractEventBus?,
    dataStore: AbstractReadWriteDataStore?,
    healthBroadcastsReceiver: AbstractHealthBroadcastsReceiver
  ) {
    self.collectionProtocol = collectionProtocol
    self.eventBus = eventBus
    self.dataStore = dataStore
    self.healthBroadcastsReceiver = healthBroadcastsReceiver
    self.healthBroadcastsReceiver.updatesDelegate = self
  }

  func startService() throws -> ServiceError? {
    guard !isServiceRunning() else { return nil }
    isRunning = true
    healthBroadcastsReceiver.beginObserving()
    return nil
  }

  func stopService() {
    isRunning = false
    healthBroadcastsReceiver.endObserving()
  }

  func isServiceRunning() -> Bool { return isRunning }

  func isAuthorized() -> Bool { return true }

  func checkPermissionStatus() {}

  private func sendHealth(event: HealthServiceData) {
    eventBus?.post(
      name: Constant.Notification.Database.WritingNewEventsToDatabase.name,
      userInfo: [
        Constant.Notification.Database.WritingNewEventsToDatabase.key: Date()
      ]
    )
    collectionProtocol?.sendEvents(
      events: [event],
      eventCollectedIn: .online
    )
  }
}

extension HealthService: HealthBroadcastsReceiverDelegate {
  func updateHealth(event: HealthServiceData) { sendHealth(event: event) }
}
