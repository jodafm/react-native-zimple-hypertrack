import UIKit

func parseDeviceToken(_ deviceToken: Data) -> String {
  var token = ""
  for i in 0 ..< deviceToken.count {
    token += String(format: "%02.2hhx", arguments: [deviceToken[i]])
  }
  return token
}

final class SilentNotificationReceiver {
  private weak var appState: AbstractAppState?
  private weak var eventBus: AbstractEventBus?
  private weak var serviceManager: AbstractServiceManager?
  private weak var initializationPipeline: InitializationPipeline?

  private var trackingCallback: ((UIBackgroundFetchResult) -> Void)?
  private var notificationTrackingState: Constant.ServerKeys.TrackingState?

  init(
    _ appState: AbstractAppState?,
    _ eventBus: AbstractEventBus?,
    _ serviceManager: AbstractServiceManager?,
    _ initializationPipeline: InitializationPipeline?
  ) {
    self.appState = appState
    self.eventBus = eventBus
    self.initializationPipeline = initializationPipeline
    trackingCallback = nil
    self.serviceManager = serviceManager
    self.eventBus?.addObserver(
      self,
      selector: #selector(manageTrackingCallback),
      name: HyperTrack.startedTrackingNotification.rawValue
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(manageTrackingCallback),
      name: HyperTrack.stoppedTrackingNotification.rawValue
    )
  }

  func registerPushDeviceToken(_ token: String) {
    guard let appState = appState else { return }
    if appState.getPushNotificationDeviceToken().isEmpty
      || appState.getPushNotificationDeviceToken() != token {
      appState.savePushNotification(deviceToken: token)
      if !appState.getPublishableKey().isEmpty {
        updateDeviceInfoWithPushToken(token)
      }
    }
  }

  func failToRegisterForRemoteNotifications(_ error: Error) {
    logNotification.error(
      "Failed to register for remote notifications with error: \(error)"
    )
  }

  func receiveRemoteNotification(
    _ userInfo: [AnyHashable: Any],
    completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard let initPipeline = self.initializationPipeline,
      let serviceManager = self.serviceManager, let appState = appState
      else { return }
    if appState.getPublishableKey().isEmpty {
      logNotification.log(
        "Did receive remote notification, when publishableKey is not set"
      )
      return
    }
    trackingCallback = completionHandler
    if let payload = userInfo[Constant.ServerKeys.SilentNotification.notificationData] as? NSDictionary {
      logNotification.log("Did receive remote notification with payload: \(payload as AnyObject)")
      if let isStartTracking = payload[Constant.ServerKeys.SilentNotification.startTracking] as? String,
         let state = Constant.ServerKeys.TrackingState(rawValue: isStartTracking) {
        notificationTrackingState = state
        switch state {
          case .stopTracking:
            if serviceManager.numberOfRunningServices()
               != serviceManager.numberOfServices() {
              manageTrackingCallback()
            }
            else {
              initPipeline.stopTracking(for: .pushStop)
            }
            return
          case .startTracking:
            if serviceManager.numberOfRunningServices()
              != serviceManager.numberOfServices()
            { initPipeline.startTracking(for: .pushStart) }
            else  {
              manageTrackingCallback()
            }
            return
        }
      }
    } else { completionHandler(.newData) }
  }

  private func updateDeviceInfoWithPushToken(_ pushToken: String) {
    guard let initializationPipeline = initializationPipeline else { return }
    logNotification.log("Updating device info with pushToken: \(pushToken)")
    initializationPipeline.updateDeviceInfo()
  }

  @objc private func manageTrackingCallback() {
    guard let trackingCallback = self.trackingCallback,
      let state = self.notificationTrackingState,
      let serviceManager = self.serviceManager
      else { return }
    switch state {
      case .startTracking:
        if serviceManager.numberOfRunningServices()
          == serviceManager.numberOfServices() {
          logNotification.log(
            "Did receive tracking notification, returning callback with .newData"
          )
          trackingCallback(.newData)
          self.trackingCallback = nil
        }
      case .stopTracking:
        logNotification.log(
          "Did receive tracking notification, returning callback with .newData"
        )
        trackingCallback(.newData)
        self.trackingCallback = nil
    }
  }
}

func registerForSilentPushNotifications() {
  UIApplication.shared.registerForRemoteNotifications()
}

func registerForSilentPushNotificationsWithDeviceToken(
  _ token: String,
  _ appState: AbstractAppState?
) {
  guard let appState = appState else { return }
  if let _ = checkBackgroundMode() { return }

  if appState.getPublishableKey().isEmpty {
    appState.savePushNotification(deviceToken: token)
  } else { Provider.silentNotificationReceiver.registerPushDeviceToken(token) }
}

func didFailToRegisterForSilentPushNotificationsWithError(
  _ error: Error,
  _ appState: AbstractAppState?
) {
  guard let appState = appState else { return }
  if appState.getPublishableKey().isEmpty {
    logNotification.error(
      "Failed to register for remote notifications with error: \(error), publishableKey is not set"
    )
  } else {
    Provider.silentNotificationReceiver.failToRegisterForRemoteNotifications(
      error
    )
  }
}

func receiveSilentPushNotification(
  _ userInfo: [AnyHashable: Any],
  _ appState: AbstractAppState?,
  completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
  guard let appState = appState else { return }
  if appState.getPublishableKey().isEmpty {
    logNotification.error(
      "Failed to receive remote notification: \(userInfo as AnyObject)"
    )
  } else {
    Provider.silentNotificationReceiver.receiveRemoteNotification(
      userInfo,
      completionHandler: completionHandler
    )
  }
}
