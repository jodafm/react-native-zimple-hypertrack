import CoreLocation
import Foundation

typealias LocationCompletionHandler = (PrivateDataAccessLevel) -> Void

final class CoreLocationManager: NSObject, AbstractLocationManager {
  fileprivate let lastCurrentLocationPermissionKey =
    "HTSDKlastCurrentLocationPermissionKey"
  fileprivate var currentPermissionState: PrivateDataAccessLevel?
  fileprivate weak var dataStore: AbstractReadWriteDataStore?
  fileprivate weak var config: AbstractLocationConfig?
  fileprivate let locationManager: CLLocationManager
  weak var updatesDelegate: LocationUpdateDelegate?
  var permissionCallback: LocationCompletionHandler?
  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate let locationFilter: LocationFilter
  var isServiceRunning: Bool = false

  var isAuthorized: Bool {
    let authorizationStatus = CLLocationManager.authorizationStatus()
    switch authorizationStatus {
      case .authorizedAlways, .authorizedWhenInUse: return true
      case .denied, .restricted, .notDetermined: return false
      @unknown default:
        logLocation.fault(
          "Failed to handle CLLocationManager.authorizationStatus: \(authorizationStatus.rawValue), status is unknown"
        )
        fatalError()
    }
  }

  init(
    config: AbstractLocationConfig?,
    eventBus: AbstractEventBus?,
    locationFilter: LocationFilter,
    dataStore: AbstractReadWriteDataStore?
  ) {
    locationManager = CLLocationManager()
    self.config = config
    self.eventBus = eventBus
    self.dataStore = dataStore
    self.locationFilter = locationFilter
    super.init()

    if let savedLocationPermissionState = dataStore?.string(
      forKey: lastCurrentLocationPermissionKey
    ) {
      currentPermissionState = PrivateDataAccessLevel(
        rawValue: savedLocationPermissionState
      )
    }

    updateConfig(config)
  }

  func updateConfig(_ config: AbstractLocationConfig?) {
    guard let config = config else { return }
    locationManager.allowsBackgroundLocationUpdates =
      config.location.backgroundLocationUpdates
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.pausesLocationUpdatesAutomatically =
      config.location.pausesLocationUpdatesAutomatically
    locationManager.activityType = CLActivityType.automotiveNavigation
    locationManager.distanceFilter = config.location.distanceFilter
    locationManager.delegate = self
    if #available(iOS 11.0, *) {
      locationManager.showsBackgroundLocationIndicator =
        config.location.showsBackgroundLocationIndicator
    }
  }

  func startService() throws {
    guard let config = config else {
      logLocation.error(
        "Failed to start LocationService with error config: nil"
      )
      return
    }
    if isAuthorized {
      if config.location.onlySignificantLocationUpdates {
        locationManager.startMonitoringSignificantLocationChanges()
      } else {
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startUpdatingLocation()
      }
      locationFilter.rest()
      isServiceRunning = true
    } else {
      try? stopService()
      isServiceRunning = false
      throw SDKError(.locationPermissionsDenied)
    }
  }

  func stopService() throws {
    guard let config = config else {
      logLocation.error("Failed to stop LocationService with error config: nil")
      return
    }
    if config.location.onlySignificantLocationUpdates {
      locationManager.stopMonitoringSignificantLocationChanges()
    } else {
      locationManager.stopMonitoringSignificantLocationChanges()
      locationManager.stopUpdatingLocation()
    }
    isServiceRunning = false
  }

  func requestPermissions(
    _ completionHandler: @escaping LocationCompletionHandler
  ) {
    permissionCallback = completionHandler
    let status = CLLocationManager.authorizationStatus()
    if locationServicesAlreadyRequested(status: status) {
      locationManager(locationManager, didChangeAuthorization: status)
    } else {
      guard let type = config?.location.permissionType else { return }
      switch type {
        case .always: locationManager.requestAlwaysAuthorization()
        default: locationManager.requestWhenInUseAuthorization()
      }
    }
  }

  func handleActivityChange(_ type: ActivityServiceData.ActivityType) {
    locationFilter.setActivity(type)
  }

  fileprivate func locationServicesAlreadyRequested(
    status: CLAuthorizationStatus
  ) -> Bool {
    switch status {
      case .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
        return true
      case .notDetermined: return false
      @unknown default:
        logLocation.fault(
          "Failed to check if loacation services was already requested with CLAuthorizationStatus: \(status.rawValue), with status unknown"
        )
        fatalError()
    }
  }

  fileprivate func authStatusToAccessLevel(_ status: CLAuthorizationStatus)
    -> PrivateDataAccessLevel {
    switch status {
      case .authorizedAlways: return .grantedAlways
      case .authorizedWhenInUse: return .grantedWhenInUse
      case .denied: return .denied
      case .restricted: return .restricted
      case .notDetermined: return .undetermined
      @unknown default:
        logLocation.fault(
          "Failed transform CLAuthorizationStatus: \(status.rawValue) to PrivateDataAccessLevel with status unknown"
        )
        fatalError()
    }
  }

  func checkPermission() {
    let status = CLLocationManager.authorizationStatus()
    sendAuthorizationStatus(status: status)
  }

  fileprivate func sendAuthorizationStatus(status: CLAuthorizationStatus) {
    var updatedStatus: CLAuthorizationStatus = status
    if CLLocationManager.locationServicesEnabled() == false {
      updatedStatus = .restricted
    }
    if currentPermissionState != authStatusToAccessLevel(updatedStatus) {
      self.currentPermissionState = authStatusToAccessLevel(updatedStatus)
      eventBus?.post(
        name: Constant.Notification.Location.PermissionChangedEvent.name,
        userInfo: [
          Constant.Notification.Location.PermissionChangedEvent.key:
            authStatusToAccessLevel(updatedStatus)
        ]
      )
      guard let currentPermissionState = self.currentPermissionState else {
        return
      }
      dataStore?.set(
        currentPermissionState.rawValue,
        forKey: lastCurrentLocationPermissionKey
      )
    }
  }
}

extension CoreLocationManager: CLLocationManagerDelegate {
  func locationManager(
    _: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    logLocation.log(
      "Location Manager did change authorization status:\(status.rawValue)"
    )
    permissionCallback?(authStatusToAccessLevel(status))
    permissionCallback = nil
    sendAuthorizationStatus(status: status)
  }

  func locationManager(
    _: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    logLocationFilter.log(
      "Received location update with locations:\(locations)"
    )
    let locationsCoordinate = locationFilter.filterСoordinates(
      current: locations
    )
    eventBus?.post(
      name: Constant.Notification.Database.WritingNewEventsToDatabase.name,
      userInfo: [
        Constant.Notification.Database.WritingNewEventsToDatabase.key: Date()
      ]
    )
    if !locationsCoordinate.isEmpty {
      updatesDelegate?.locationUpdates(locationsCoordinate)
    }
  }

  func locationManager(
    _: CLLocationManager,
    didFailWithError error: Error
  ) {
    logLocation.error(
      "Failed to update locations with CLLocationManager error: \(error)"
    )
  }
}
