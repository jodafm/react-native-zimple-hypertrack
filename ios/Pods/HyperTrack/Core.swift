import CoreLocation
import CoreMotion
import Foundation
import UIKit

private let backgroundModesKey = "UIBackgroundModes"
private let backgroundModeLocation = "location"
private let isiPhone = "iPhone"

func checkForFatalErrors() -> HyperTrack.FatalError? {
  #if targetEnvironment(simulator)
    return .developmentError(.runningOnSimulatorUnsupported)
  #endif
  if let error = checkBackgroundMode() { return .developmentError(error) }
  if !UIDevice.current.model.hasPrefix(isiPhone) {
    return .productionError(.locationServicesUnavalible)
  }
  if !CMMotionActivityManager.isActivityAvailable() {
    Provider.eventBus.post(
      name: Constant.Notification.Health.GenerateOutageEvent.name,
      userInfo: [
        Constant.Notification.Activity.PermissionChangedEvent.key:
          SDKError(.activityServicesDisabled)
      ]
    )
    return .productionError(.motionActivityServicesUnavalible)
  }
  if #available(iOS 11.0, *) {
    switch CMMotionActivityManager.authorizationStatus() {
      case .denied:
        Provider.eventBus.post(
          name: Constant.Notification.Health.GenerateOutageEvent.name,
          userInfo: [
            Constant.Notification.Health.GenerateOutageEvent.key:
              SDKError(.activityPermissionsDenied)
          ]
        )
        return .productionError(.motionActivityPermissionsDenied)
      default: return nil
    }
  }
  return nil
}

func checkBackgroundMode() -> HyperTrack.DevelopmentError? {
  if let infoDict = Bundle.main.infoDictionary,
    let backgroundModeList = infoDict[backgroundModesKey] as? [String] {
    let searchResult = backgroundModeList.filter {
      $0 == backgroundModeLocation
    }
    if searchResult.isEmpty {
      return .missingLocationUpdatesBackgroundModeCapability
    } else { return nil }
  } else { return .missingLocationUpdatesBackgroundModeCapability }
}

final class Core {
  static let shared = Core()
  private init() {}

  var deviceIdentifier: UUID {
    return UUID(uuidString: Provider.appState.getDeviceId())!
  }

  var isTracking: Bool {
    switch Provider.appState.userTrackingBehaviour {
      case .resumed: return true
      default: return false
    }
  }

  func setup() { Provider.initPipeline.preInit() }

  func savePublishableKey(_ publishableKey: String) {
    Provider.initPipeline.checkPublishibleKey(publishableKey)
  }

  func setPublishableKey() {
    Provider.initPipeline.initializeSDK()
  }

  func setName(_ name: String) {
    Provider.appState.saveCurrentSessionDevice(name: name)
  }

  func setMetadata(_ metadata: HyperTrack.Metadata) {
    Provider.appState.saveCurrentSessionDevice(metaData: metadata.rawValue)
  }

  func syncDeviceSettings() { Provider.deviceSettings.getSettings() }

  func startTracking() {
    Provider.initPipeline.startTracking(for: .trackingStart)
  }

  func stopTracking() { Provider.initPipeline.stopTracking(for: .trackingStop) }

  func setTripMarker(_ marker: HyperTrack.Metadata) {
    Provider.collectionPipeline.tripMarkerEvent(marker.rawValue)
  }
}
