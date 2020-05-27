import CoreLocation
import Foundation

protocol AbstractLocationService: AbstractService {
  func requestPermissions(
    _ completionHandler: @escaping LocationCompletionHandler
  )
}

protocol LocationUpdateDelegate: AnyObject {
  func locationUpdates(_ locations: [CLLocation])
}

protocol AbstractLocationManager {
  var isServiceRunning: Bool { get }
  var isAuthorized: Bool { get }
  var updatesDelegate: LocationUpdateDelegate? { get set }
  func startService() throws
  func stopService() throws
  func updateConfig(_ config: AbstractLocationConfig?)
  func requestPermissions(
    _ completionHandler: @escaping LocationCompletionHandler
  )
  func handleActivityChange(_ type: ActivityServiceData.ActivityType)
  func checkPermission()
}

final class LocationService: AbstractLocationService, LocationUpdateDelegate {
  fileprivate var locationManager: AbstractLocationManager
  fileprivate weak var config: AbstractLocationConfig?
  fileprivate weak var appState: AbstractAppState?
  fileprivate weak var locationUpdatesDelegate: LocationUpdateDelegate?
  fileprivate var currentPermissionState: PrivateDataAccessLevel?
  weak var collectionProtocol: AbstractCollectionPipeline?
  weak var eventBus: AbstractEventBus?

  init(
    config: AbstractLocationConfig?,
    locationManager: AbstractLocationManager,
    collection: AbstractCollectionPipeline?,
    eventBus: AbstractEventBus?,
    appState: AbstractAppState?
  ) {
    self.config = config
    self.appState = appState
    self.locationManager = locationManager
    collectionProtocol = collection
    self.eventBus = eventBus
    self.locationManager.updatesDelegate = self
    self.eventBus?.addObserver(
      self,
      selector: #selector(updateConfig(_:)),
      name: Constant.Notification.Config.ConfigChangedEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(handleActivityChange(_:)),
      name: Constant.Notification.Activity.ActivityChangedEvent.name
    )
  }

  @objc private func updateConfig(_: Notification) {
    locationManager.updateConfig(config)
  }

  @objc private func handleActivityChange(_ notification: Notification) {
    guard
      let type =
      notification.userInfo?[
        Constant.Notification.Activity.ActivityChangedEvent.key
      ]
      as? ActivityServiceData.ActivityType
      else { return }
    locationManager.handleActivityChange(type)
  }

  private func mapLocationsToLocationServiceData(_ locations: [CLLocation])
    -> [LocationServiceData] {
    guard let locations = Array(NSOrderedSet(array: locations)) as? [CLLocation]
      else { return [] }
    return LocationServiceData.getData(locations)
  }

  func locationUpdates(_ locations: [CLLocation]) {
    collectionProtocol?.sendEvents(
      events: mapLocationsToLocationServiceData(locations)
    )
    locationUpdatesDelegate?.locationUpdates(locations)
    guard let lastCoord = locations.last else { return }
    eventBus?.post(
      name: Constant.Notification.Location.NewEventAvalible.name,
      userInfo: [
        Constant.Notification.Location.NewEventAvalible.key: LocationData(
          lastCoord
        )
      ]
    )
  }

  func requestPermissions(
    _ completionHandler: @escaping LocationCompletionHandler
  ) { locationManager.requestPermissions(completionHandler) }

  func isAuthorized() -> Bool { return locationManager.isAuthorized }

  func setLocationUpdatesDelegate(_ delegate: LocationUpdateDelegate?) {
    locationUpdatesDelegate = delegate
  }

  func checkPermissionStatus() { locationManager.checkPermission() }

  func startService() throws -> ServiceError? {
    do { try locationManager.startService() } catch { throw error }
    return nil
  }

  func stopService() {
    do { try locationManager.stopService() } catch {}
  }

  func isServiceRunning() -> Bool { return locationManager.isServiceRunning }
}
