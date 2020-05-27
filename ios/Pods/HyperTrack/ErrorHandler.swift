import Foundation

protocol AbstractErrorHandler: AnyObject {
  func handleError(_ error: SDKError)
  func resetNetworkErrorFlag()
  func resetTrialEndedErrorFlag()
}

final class ErrorHandler {
  private let networkErrorKey = "hypertrack.networkErrorKey"
  private let trialEndedErrorKey = "hypertrack.trialEndedErrorKey"

  private weak var eventBus: AbstractEventBus?
  private weak var dataStore: AbstractReadWriteDataStore?

  private var isNetworkErrorSent: Bool {
    get { return dataStore?.bool(forKey: networkErrorKey) ?? false }
    set { dataStore?.set(newValue, forKey: networkErrorKey) }
  }

  private var isTrialEndedErrorSent: Bool {
    get { return dataStore?.bool(forKey: trialEndedErrorKey) ?? false }
    set { dataStore?.set(newValue, forKey: trialEndedErrorKey) }
  }

  init(
    _ eventBus: AbstractEventBus?,
    _ dataStore: AbstractReadWriteDataStore?
  ) {
    self.eventBus = eventBus
    self.dataStore = dataStore

    self.eventBus?.addObserver(
      self,
      selector: #selector(trackingStopped),
      name: Constant.Notification.Tracking.Stopped.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(trackingStarted),
      name: Constant.Notification.Tracking.Started.name
    )
  }

  @objc private func trackingStarted() {
    isNetworkErrorSent = false
    isTrialEndedErrorSent = false

    eventBus?.addObserver(
      self,
      selector: #selector(handleActivityPermissionsChanges(_:)),
      name: Constant.Notification.Activity.PermissionChangedEvent.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(handleLocationPermissionsChanges(_:)),
      name: Constant.Notification.Location.PermissionChangedEvent.name
    )
  }

  @objc private func trackingStopped() {
    eventBus?.removeObserver(
      self,
      name: Constant.Notification.Activity.PermissionChangedEvent.name
    )
    eventBus?.removeObserver(
      self,
      name: Constant.Notification.Location.PermissionChangedEvent.name
    )
  }
}

extension ErrorHandler: AbstractErrorHandler {
  @objc func handleActivityPermissionsChanges(_ notification: Notification) {
    guard
      let accessLevel =
      notification.userInfo?[
        Constant.Notification.Activity.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    switch accessLevel {
      case .denied:
        eventBus?.post(
          name: Constant.Notification.SDKError.Unrestorable.name,
          error: HyperTrack.UnrestorableError.motionActivityPermissionsDenied
        )
      case .restricted:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.motionActivityServicesDisabled
        )
      case .granted, .grantedAlways, .grantedWhenInUse: break
      default:
        logErrorHandler.error(
          "invalid activity handle error: \(accessLevel.localizedValue())"
        )
    }
  }

  @objc func handleLocationPermissionsChanges(_ notification: Notification) {
    guard
      let accessLevel =
      notification.userInfo?[
        Constant.Notification.Location.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    switch accessLevel {
      case .denied:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.locationPermissionsDenied
        )
      case .restricted:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.locationServicesDisabled
        )
      case .granted, .grantedAlways, .grantedWhenInUse: break
      default:
        logErrorHandler.error(
          "invalid location handle error: \(accessLevel.localizedValue())"
        )
    }
  }

  func handleError(_ error: SDKError) {
    switch error.type {
      case .forbidden:
        if !isTrialEndedErrorSent {
          eventBus?.post(
            name: Constant.Notification.SDKError.Restorable.name,
            error: HyperTrack.RestorableError.trialEnded
          )
          isTrialEndedErrorSent = true
        }
      case .invalidToken:
        eventBus?.post(
          name: Constant.Notification.SDKError.Unrestorable.name,
          error: HyperTrack.UnrestorableError.invalidPublishableKey
        )
      case .networkDisconnectedGreater12Hours:
        if !isNetworkErrorSent {
          eventBus?.post(
            name: Constant.Notification.SDKError.Restorable.name,
            error: HyperTrack.RestorableError.networkConnectionUnavailable
          )
          isNetworkErrorSent = true
        }
      case .networkDisconnected:
        // TODO: This case is unreachable, remove in refactor
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.networkConnectionUnavailable
        )
      case .locationServicesDisabled:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.locationServicesDisabled
        )
      case .locationPermissionsDenied:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.locationPermissionsDenied
        )
      case .activityServicesDisabled:
        eventBus?.post(
          name: Constant.Notification.SDKError.Restorable.name,
          error: HyperTrack.RestorableError.motionActivityServicesDisabled
        )
      case .activityPermissionsDenied:
        eventBus?.post(
          name: Constant.Notification.SDKError.Unrestorable.name,
          error: HyperTrack.UnrestorableError.motionActivityPermissionsDenied
        )
      default:
        logErrorHandler.error(
          "invalid handle error: \(prettyPrintSDKError(error))"
        )
    }
  }

  func resetNetworkErrorFlag() { isNetworkErrorSent = false }

  func resetTrialEndedErrorFlag() { isTrialEndedErrorSent = false }
}
