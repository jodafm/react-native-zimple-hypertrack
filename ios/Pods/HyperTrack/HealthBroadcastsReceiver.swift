import Foundation
//
//  HealthBroadcastsReceiver.swift
//  CocoaLumberjack
//
//  Created by Dmytro Shapovalov on 2/8/19.
//
import UIKit

protocol HealthBroadcastsReceiverDelegate: AnyObject {
  func updateHealth(event: HealthServiceData)
}

final class HealthBroadcastsReceiver: NSObject,
  AbstractHealthBroadcastsReceiver {
  fileprivate let resumptionKey = Constant.Health.Value.Resumption.key

  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate weak var appState: AbstractAppState?
  fileprivate weak var dataStore: AbstractReadWriteDataStore?
  fileprivate weak var reachability: AbstractReachabilityManager?
  fileprivate var batteryLevel: Float { return UIDevice.current.batteryLevel }
  fileprivate var batteryState: UIDevice.BatteryState {
    return UIDevice.current.batteryState
  }

  fileprivate var activityPermissionState: Permissions = .denied
  fileprivate var locationPermissionState: Permissions = .denied
  weak var updatesDelegate: HealthBroadcastsReceiverDelegate?

  init(
    appState: AbstractAppState?,
    eventBus: AbstractEventBus?,
    dataStore: AbstractReadWriteDataStore?,
    reachability: AbstractReachabilityManager?
  ) {
    super.init()
    self.eventBus = eventBus
    self.appState = appState
    self.dataStore = dataStore
    self.reachability = reachability
    UIDevice.current.isBatteryMonitoringEnabled = true
    if let activityPermissionValue = dataStore?.integer(
      forKey: Constant.Health.savedActivityPermissionState
    ) {
      activityPermissionState = Permissions(
        rawValue: activityPermissionValue
      ) ?? .denied
    }
    if let locationPermissionValue = dataStore?.integer(
      forKey: Constant.Health.savedLocationPermissionState
    ) {
      locationPermissionState = Permissions(
        rawValue: locationPermissionValue
      ) ?? .denied
    }
    addObserverForTracking()
  }

  // MARK: Observers

  private func addObserverForTracking() {
    eventBus?.addObserver(
      self,
      selector: #selector(eraseTrackingResumptionData),
      name: Constant.Notification.AuthToken.Inactive.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(stopTrackingEvent(_:)),
      name: Constant.Notification.Tracking.Stopped.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(startTrackingEvent(_:)),
      name: Constant.Notification.Tracking.Started.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(activityPermissionEvent(_:)),
      name: Constant.Notification.Activity.PermissionChangedEvent.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(locationPermissionEvent(_:)),
      name: Constant.Notification.Location.PermissionChangedEvent.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(appTerminatedEvent),
      name: UIApplication.willTerminateNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(didEnterBackgroundEvent),
      name: UIApplication.didEnterBackgroundNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(willEnterForegroundEvent),
      name: UIApplication.willEnterForegroundNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(didFinishLaunchingEvent),
      name: UIApplication.didFinishLaunchingNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(didBecomeActiveEvent),
      name: UIApplication.didBecomeActiveNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(willResignActiveEvent),
      name: UIApplication.willResignActiveNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(significantTimeChangeEvent),
      name: UIApplication.significantTimeChangeNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(backgroundRefreshStatusDidChangeEvent),
      name: UIApplication.backgroundRefreshStatusDidChangeNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(serviceOutageGeneration(_:)),
      name: Constant.Notification.Health.GenerateOutageEvent.name
    )
  }

  func beginObserving() {
    eraseBatteryData()
    batteryEvent()
    eventBus?.addObserver(
      self,
      selector: #selector(batteryEvent),
      name: UIDevice.batteryStateDidChangeNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(batteryEvent),
      name: UIDevice.batteryLevelDidChangeNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(reachabilityEvent(_:)),
      name: Constant.Notification.Network.ReachabilityEvent.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(receiveMemoryWarning),
      name: UIApplication.didReceiveMemoryWarningNotification.rawValue
    )
    eventBus?.addObserver(
      self,
      selector: #selector(storedEventData(_:)),
      name: Constant.Notification.Database.WritingNewEventsToDatabase.name
    )
  }

  func endObserving() {
    eventBus?.removeObserver(
      self,
      name: UIDevice.batteryStateDidChangeNotification.rawValue
    )
    eventBus?.removeObserver(
      self,
      name: UIDevice.batteryLevelDidChangeNotification.rawValue
    )
    eventBus?.removeObserver(
      self,
      name: Constant.Notification.Network.ReachabilityEvent.name
    )
    eventBus?.removeObserver(
      self,
      name: UIApplication.didReceiveMemoryWarningNotification.rawValue
    )
    eventBus?.removeObserver(
      self,
      name: Constant.Notification.Database.WritingNewEventsToDatabase.name
    )
  }

  @objc private func batteryEvent() {
    guard batteryState != .unknown else { return }
    let input = getTypeFromBatteryState(state: batteryState)
    checkDataStoreStatusUpdate(input: input, date: Date())
  }

  @objc private func reachabilityEvent(_: Notification) {
    checkOnlineConnectionWhenStarted()
  }

  @objc private func storedEventData(_ notif: Notification) {
    guard
      let lastEventDate =
      notif.userInfo?[
        Constant.Notification.Database.WritingNewEventsToDatabase.key
      ]
      as? Date
      else { return }
    dataStore?.set(lastEventDate, forKey: Constant.Health.Key.lastEventDateKey)
  }

  // MARK: Tracking Related Methods

  @objc private func stopTrackingEvent(_ notif: Notification) {
    guard
      let trackingReason =
      notif.userInfo?[Constant.Notification.Tracking.TrackingReason.key]
      as? TrackingReason
      else { return }
    guard let input = self.getTypeFromTrackingReason(reason: trackingReason)
      else { return }
    checkDataStoreSystemUpdate(input: input, date: Date())
  }

  @objc private func startTrackingEvent(_ notif: Notification) {
    guard
      let trackingReason =
      notif.userInfo?[Constant.Notification.Tracking.TrackingReason.key]
      as? TrackingReason
      else { return }
    guard let input = self.getTypeFromTrackingReason(reason: trackingReason)
      else { return }
    checkDataStoreSystemUpdate(input: input, date: Date())
  }

  // MARK: Location Related Methods

  @objc private func locationPermissionEvent(_ notif: Notification) {
    guard
      let accessLevel =
      notif.userInfo?[
        Constant.Notification.Location.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    guard
      let input = self.getTypeFromLocationPermission(accessLevel: accessLevel)
      else { return }
    checkDataStoreSystemUpdate(input: input, date: Date())
  }

  // MARK: Activity Related Methods

  @objc private func activityPermissionEvent(_ notif: Notification) {
    guard
      let accessLevel =
      notif.userInfo?[
        Constant.Notification.Activity.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    guard
      let input = self.getTypeFromActivityPermission(accessLevel: accessLevel)
      else { return }
    checkDataStoreSystemUpdate(input: input, date: Date())
  }

  // MARK: Data Store Methods

  private func checkDataStoreSystemUpdate(input: HealthType, date: Date) {
    savePermissions(state: input)
    guard let intent = appState?.userTrackingBehaviour else { return }
    guard let pk = appState?.getPublishableKey(), !pk.isEmpty else { return }

    let savedValue = dataStore?.string(
      forKey: Constant.Health.healthSystemUpdate
    ) ?? ""
    let trackingReason = TrackingReason(
      rawValue: dataStore?.integer(
        forKey: Constant.Health.savedStartTrackingReason
      ) ?? 0
    )

    logGeneral.log(
      "Updating state with\nPrevious Event: \(savedValue)\nIntent: \(intent)\nPermissions: \(getPermissionsState())\nTracking Status: \(getTrackingStatus())\nSystem Events: \(input.toSystemEvents())"
    )

    switch (
      (
        savedValue,
        intent,
        getPermissionsState(),
        getTrackingStatus()
      ), input.toSystemEvents()
    ) {
      case (("", .resumed, .granted, .notTracking), .permissionGranted):
        updateHealthValue(
          input: HealthType.makeTrackingState(reason: trackingReason),
          date: date
        )
      case ((_, .resumed, .granted, .tracking), .permissionGranted):
        updateHealthValue(input: input, date: date)
      case ((_, .paused, .granted, .notTracking), .trackingStopped):
        updateHealthValue(input: input, date: date)
      case ((_, .resumed, .granted, .tracking), .trackingStarted):
        updateHealthValue(input: input, date: date)
      case ((_, .resumed, .denied, .tracking), .permissionDenied):
        updateHealthValue(input: input, date: date)
      case ((_, .resumed, .granted, .notTracking), .permissionGranted):
        updateHealthValue(input: input, date: date)
      case ((_, .resumed, .granted, .notTracking), .trackingStopped):
        updateHealthValue(input: input, date: date)
      case ((resumptionKey, .resumed, .denied, .notTracking), .permissionDenied):
        updateHealthValue(input: input, date: date)
      default: break
    }
  }

  private func checkDataStoreStatusUpdate(input: HealthType, date: Date) {
    let healthValues = input.healthValues()
    let savedValue = dataStore?.string(forKey: healthValues.key) ?? ""
    if savedValue != healthValues.hint {
      dataStore?.set(healthValues.hint, forKey: healthValues.key)
      updatesDelegate?.updateHealth(
        event: HealthServiceData(healthType: input, recordedDate: date)
      )
    }
  }

  private func checkOnlineConnectionWhenStarted() {
    if let isReachable = reachability?.isReachable, isReachable {
      appState?.saveLastOnlineSession(info: (date: Date(), isReachable: true))
      logHealth.log("Application isReachable: true")
    } else {
      appState?.saveLastOnlineSession(info: (date: Date(), isReachable: false))
      logHealth.log("Application isReachable: false")
    }
  }

  private func eraseBatteryData() {
    dataStore?.set("", forKey: Constant.Health.Key.batteryState)
  }

  @objc private func eraseTrackingResumptionData() {
    dataStore?.set("", forKey: Constant.Health.healthSystemUpdate)
  }

  deinit { self.eventBus?.removeObserver(self) }
}

extension HealthBroadcastsReceiver {
  private func getTypeFromActivityPermission(
    accessLevel: PrivateDataAccessLevel
  ) -> HealthType? {
    switch accessLevel {
      case .unavailable: return HealthType.activityUnavailable
      case .restricted: return HealthType.activityDisabled
      case .denied, .undetermined: return HealthType.activityPermissionDenied
      case .granted, .grantedAlways, .grantedWhenInUse:
        return HealthType.activityPermissionGranted
    }
  }

  private func getTypeFromLocationPermission(
    accessLevel: PrivateDataAccessLevel
  ) -> HealthType? {
    switch accessLevel {
      case .restricted: return HealthType.locationDisabled
      case .denied, .undetermined: return HealthType.locationPermissionDenied
      case .granted, .grantedAlways, .grantedWhenInUse:
        return HealthType.locationPermissionGranted
      default: return nil
    }
  }

  private func getTypeFromTrackingReason(reason: TrackingReason) -> HealthType? {
    switch reason {
      case .pushStart: return HealthType.trackingPushStarted
      case .pushStop: return HealthType.trackingPushStopped
      case .trackingStart: return HealthType.trackingStarted
      case .trackingStop: return HealthType.trackingStopped
      case .settingsStart: return HealthType.trackingSettingsStarted
      case .settingsStop: return HealthType.trackingSettingsStopped
      case .trialEnded: return nil
    }
  }

  private func getTypeFromBatteryState(state: UIDevice.BatteryState)
    -> HealthType {
    switch state {
      case .charging, .full: return HealthType.batteryCharging
      case .unplugged, .unknown:
        var type = HealthType.batteryNormal
        if batteryLevel <= Constant.lowBatteryValue { type = .batteryLow }
        return type
      @unknown default:
        logHealth.fault(
          "Failed to convert UIDevice.BatteryState: \(state) to HealthType, state is unknown"
        )
        fatalError()
    }
  }

  private func savePermissions(state: HealthType) {
    switch state {
      case .locationDisabled, .locationPermissionDenied:
        locationPermissionState = .denied
      case .locationPermissionGranted: locationPermissionState = .granted
      case .activityDisabled, .activityUnavailable, .activityPermissionDenied:
        activityPermissionState = .denied
      case .activityPermissionGranted: activityPermissionState = .granted
      default: break
    }
    dataStore?.set(
      locationPermissionState.rawValue,
      forKey: Constant.Health.savedLocationPermissionState
    )
    dataStore?.set(
      activityPermissionState.rawValue,
      forKey: Constant.Health.savedActivityPermissionState
    )
  }

  private func getPermissionsState() -> Permissions {
    switch (locationPermissionState, activityPermissionState) {
      case (.granted, .granted): return .granted
      default: return .denied
    }
  }

  private func getTrackingStatus() -> TrackingStatus {
    if Provider.serviceManager.numberOfRunningServices()
      == Provider.serviceManager.numberOfServices()
    { return .tracking }
    return .notTracking
  }

  private func updateHealthValue(input: HealthType?, date: Date) {
    let savedValue = dataStore?.string(
      forKey: Constant.Health.healthSystemUpdate
    )
    guard let event = input else { return }
    var inputDate = date

    switch event {
      case .trackingStarted, .trackingPushStarted, .locationPermissionGranted,
           .activityPermissionGranted:
        inputDate = appState?.resumptionDate ?? date
        /// Erease previous data about outage
        dataStore?.set(
          Constant.Health.Value.Resumption.key,
          forKey: Constant.Health.healthServiceOutageGenerationUpdate
        )
      case .activityDisabled, .activityPermissionDenied, .activityUnavailable,
           .locationDisabled, .locationPermissionDenied:
        /// set value for outage when user attempts to start tracking when tracking is stopped
        /// needed for avoiding generation outage twice
        dataStore?.set(
          Constant.Health.Value.Outage.key,
          forKey: Constant.Health.healthServiceOutageGenerationUpdate
        )
      default: break
    }
    if savedValue != event.healthValues().key {
      dataStore?.set(
        event.healthValues().key,
        forKey: Constant.Health.healthSystemUpdate
      )
      updatesDelegate?.updateHealth(
        event: HealthServiceData(healthType: event, recordedDate: inputDate)
      )
    }
  }
}

extension HealthBroadcastsReceiver {
  // MARK: Life cycle logs

  @objc private func receiveMemoryWarning() {
    logLifecycle.error("Application Did Receive Memory Warning")
  }

  @objc private func appTerminatedEvent() {
    logLifecycle.fault("Application Will Terminate")
  }

  // didEnterBackgroundNotification
  @objc private func didEnterBackgroundEvent() {
    logLifecycle.log("Application Did Enter Background")
  }

  // willEnterForegroundNotification
  @objc private func willEnterForegroundEvent() {
    logLifecycle.log("Application Will Enter Foreground")
  }

  // didFinishLaunchingNotification
  @objc private func didFinishLaunchingEvent() {
    logLifecycle.log("Application Did Finish Launching")
  }

  // didBecomeActiveNotification
  @objc private func didBecomeActiveEvent() {
    logLifecycle.log("Application Did Become Active")
  }

  // willResignActiveNotification
  @objc private func willResignActiveEvent() {
    logLifecycle.log("Application Will Resign Active")
  }

  // significantTimeChangeNotification
  @objc private func significantTimeChangeEvent() {
    logLifecycle.log("Significant Time Change")
  }

  // backgroundRefreshStatusDidChangeNotification
  @objc private func backgroundRefreshStatusDidChangeEvent() {
    logLifecycle.log("Application Background Refresh Status Did Change")
  }
}

extension HealthBroadcastsReceiver {
  // Generate outage when user attempts to start tracking when tracking is stopped
  @objc private func serviceOutageGeneration(_ notif: Notification) {
    guard
      let error =
      notif.userInfo?[Constant.Notification.Health.GenerateOutageEvent.key]
      as? SDKError
      else { return }
    switch error.type {
      case .locationServicesDisabled:
        updateServiceOutageGenerateHealthValue(
          input: HealthType.locationDisabled,
          date: Date()
        )
      case .locationPermissionsDenied:
        updateServiceOutageGenerateHealthValue(
          input: HealthType.locationPermissionDenied,
          date: Date()
        )
      case .activityServicesDisabled:
        updateServiceOutageGenerateHealthValue(
          input: HealthType.activityDisabled,
          date: Date()
        )
      case .activityPermissionsDenied:
        updateServiceOutageGenerateHealthValue(
          input: HealthType.activityPermissionDenied,
          date: Date()
        )
      default:
        logHealth.error(
          "invalid handle service Outage : \(prettyPrintSDKError(error))"
        )
    }
  }

  private func updateServiceOutageGenerateHealthValue(
    input: HealthType?,
    date: Date
  ) {
    let savedValue = dataStore?.string(
      forKey: Constant.Health.healthServiceOutageGenerationUpdate
    )
    guard let event = input else { return }
    if savedValue != event.healthValues().key {
      logHealth.error("Event putage was generated - \(event)")
      dataStore?.set(
        event.healthValues().key,
        forKey: Constant.Health.healthServiceOutageGenerationUpdate
      )
      updatesDelegate?.updateHealth(
        event: HealthServiceData(healthType: event, recordedDate: date)
      )
    }
  }
}
