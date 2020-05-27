import CoreMotion
import Foundation
import UIKit

protocol EventUpdatesDelegate: AnyObject {
  func didChangeEvent(_ dict: Payload, serviceType: Config.Services.ServiceType)
}

final class ActivityService: AbstractService {
  fileprivate let activityQueueName = "HTActivityQueue"
  fileprivate let promptKey = "HTSDKMotionPermissionMotionPromptKey"
  fileprivate let lastActivityTypeKey = "HTSDKMotionLastActivityTypeKey"
  fileprivate let receivedKey = "HTSDKMotionPermissionMotionReceivedKey"
  fileprivate let lastCurrentActivityPermissionKey =
    "HTSDKlastCurrentActivityPermissionKey"
  fileprivate let pedometer = CMPedometer()
  fileprivate var totalStepCountFromStartTracking: Int = 0
  fileprivate var startTrackingStepDate = Date()
  fileprivate var lastSentTrackingStepDate = Date()
  fileprivate var lastPedometerData: CMPedometerData?
  fileprivate let activityManager = CMMotionActivityManager()
  fileprivate var isRunning = false
  fileprivate var lastActivityType: ActivityServiceData.ActivityType?
  fileprivate weak var dataStore: AbstractReadWriteDataStore?
  fileprivate weak var delegate: EventUpdatesDelegate?
  fileprivate var currentPermissionState: PrivateDataAccessLevel?
  fileprivate var repeatTimer: GCDRepeatingTimer?
  fileprivate let checkInterval: TimeInterval

  fileprivate lazy var activityQueue: OperationQueue = {
    var queue = OperationQueue()
    queue.name = self.activityQueueName
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  weak var collectionProtocol: AbstractCollectionPipeline?
  weak var eventBus: AbstractEventBus?
  weak var appState: AbstractAppState?

  init(
    withCollectionProtocol collectionProtocol: AbstractCollectionPipeline?,
    appState: AbstractAppState?,
    eventBus: AbstractEventBus?,
    dataStore: AbstractReadWriteDataStore?
  ) {
    self.appState = appState
    self.collectionProtocol = collectionProtocol
    self.eventBus = eventBus
    self.dataStore = dataStore
    checkInterval = Constant.Config.Activity.checkPermissionInterval
    self.eventBus?.addObserver(
      self,
      selector: #selector(ActivityService.appWillComeToForeground),
      name: UIApplication.willEnterForegroundNotification.rawValue
    )
    if let savedActivityPermissionState = dataStore?.string(
      forKey: lastCurrentActivityPermissionKey
    ) {
      currentPermissionState = PrivateDataAccessLevel(
        rawValue: savedActivityPermissionState
      )
    }
    if repeatTimer == nil {
      repeatTimer = GCDRepeatingTimer(timeInterval: checkInterval)
    }
    startPermissionChecking()
  }

  func startPermissionChecking() {
    repeatTimer?.eventHandler = { [weak self] in
      guard let self = self else { return }
      self.checkActivityPermission()
    }
    repeatTimer?.resume()
  }

  func startService() throws -> ServiceError? {
    if isAuthorized() {
      repeatTimer?.suspend()
      guard !isRunning else { return nil }
      isRunning = true
      activityManager.queryActivityStarting(
        from: Date().addingTimeInterval(
          -Constant.Config.Activity.requestActivityInterval
        ),
        to: Date(),
        to: activityQueue
      ) { [weak self] list, _ in
        guard let activityList = list else { return }
        let filteredActivity = activityList.filter {
          ActivityServiceData.ActivityType(activity: $0).isSupported
        }.filter { $0.confidence == .high }
        let lastActitivty = filteredActivity.last
        var tmpActivity: CMMotionActivity?
        guard let activity = lastActitivty else { return }
        for item in filteredActivity.reversed() {
          if item.automotive == activity.automotive,
            item.stationary == activity.stationary,
            item.walking == activity.walking,
            item.running == activity.running, item.cycling == activity.cycling
          { tmpActivity = item } else { break }
        }
        if let activity = tmpActivity {
          logActivity.log(
            "Received activity update from queryActivityStarting with activity: \(activity)"
          )
          self?.handleActivityReceived(activity: activity)
        }
      }
      activityManager.startActivityUpdates(to: activityQueue) {
        [weak self] activity in
        if let activity = activity {
          logActivity.log("Received activity update with activity: \(activity)")
          self?.handleActivityReceived(activity: activity)
        }
      }
      startTrackingStep()
      return nil
    } else {
      if accessLevel != .undetermined { stopService() }
      switch accessLevel {
        case .undetermined: throw ServiceError.permissionNotTaken
        case .unavailable: throw ServiceError.hardwareNotSupported
        case .denied, .restricted: throw ServiceError.userDenied
        default: return nil
      }
    }
  }

  func stopService() {
    guard isAuthorized() else { return }
    activityManager.stopActivityUpdates()
    pedometer.stopUpdates()
    isRunning = false
  }

  func isServiceRunning() -> Bool { return isRunning }

  func isAuthorized() -> Bool {
    switch accessLevel {
      case .granted, .grantedAlways, .grantedWhenInUse: return true
      default: return false
    }
  }

  private func startTrackingStep() {
    totalStepCountFromStartTracking = 0
    startTrackingStepDate = Date()

    if CMPedometer.isStepCountingAvailable() {
      pedometer.startUpdates(
        from: startTrackingStepDate,
        withHandler: { data, error in
          logActivity.log(
            "Received pedometer update with data: \(String(describing: data)) error: \(String(describing: error))"
          )
          if error == nil {
            if let lastPedometerData = self.lastPedometerData, let data = data,
              lastPedometerData.numberOfSteps.intValue
              == data.numberOfSteps.intValue
            {} else { self.lastPedometerData = data }
          } else if let error = error {
            logActivity.error(
              "Failed to start pedometer updates from startTrackingStepDate: \(self.startTrackingStepDate) with error: \(error)"
            )
          }

          guard let data = data,
            let restartDate = Calendar.current.date(
              byAdding: .day,
              value: 1,
              to: self.startTrackingStepDate
            )
            else { return }
          if data.startDate >= restartDate {
            self.pedometer.stopUpdates()
            self.startTrackingStep()
          }
        }
      )
    } else {
      logActivity.error(
        "Failed to start tracking steps because step counting unavailable"
      )
    }
  }

  fileprivate func handleActivityReceived(activity: CMMotionActivity) {
    var event = ActivityServiceData(
      activityId: UUID().uuidString,
      osActivity: activity,
      recordedDate: activity.startDate
    )

    if activity.confidence == .high,
      lastActivityType?.rawValue != event.data.value,
      let type = event.data.type, type.isSupported {
      if let pedometerData = lastPedometerData {
        if lastSentTrackingStepDate != pedometerData.endDate {
          let timeDelta = activity.startDate - pedometerData.endDate
          let stepDelta = pedometerData.numberOfSteps.intValue
            - totalStepCountFromStartTracking
          event.data.pedometer = StepsData(
            timeDelta: timeDelta.toMilliseconds(),
            numberOfSteps: stepDelta
          )
          totalStepCountFromStartTracking = pedometerData.numberOfSteps.intValue
          lastSentTrackingStepDate = pedometerData.endDate
        }
      }
      collectionProtocol?.sendEvents(events: [event])
      lastActivityType = type
      dataStore?.set(event.data.value, forKey: lastActivityTypeKey)
      eventBus?.post(
        name: Constant.Notification.Activity.ActivityChangedEvent.name,
        userInfo: [
          Constant.Notification.Activity.ActivityChangedEvent.key: type
        ]
      )
    }
    delegate?.didChangeEvent(
      ["sensor_data": activity, "inferred": event.data.value],
      serviceType: .activity
    )
    eventBus?.post(
      name: Constant.Notification.Database.WritingNewEventsToDatabase.name,
      userInfo: [
        Constant.Notification.Database.WritingNewEventsToDatabase.key: Date()
      ]
    )
  }

  // MARK: Background/ Foreground Methods

  @objc fileprivate func appWillComeToForeground() { checkPermissionStatus() }

  func setEventUpdatesDelegate(_ delegate: EventUpdatesDelegate?) {
    self.delegate = delegate
  }
}

extension ActivityService: PrivateDataAccessProvider {
  var accessLevel: PrivateDataAccessLevel {
    var status: PrivateDataAccessLevel = .undetermined
    if CMMotionActivityManager.isActivityAvailable() == false {
      // hardware level not available
      status = .unavailable
    } else {
      if #available(iOS 11.0, *) {
        switch CMMotionActivityManager.authorizationStatus() {
          case .notDetermined: status = .undetermined
          case .restricted: status = .restricted
          case .denied: status = .denied
          case .authorized: status = .granted
          @unknown default: fatalError()
        }
      } else {
        if dataStore?.string(forKey: promptKey) == nil {
          status = .undetermined
        } else {
          // Prompt has been presented in the past
          if dataStore?.string(forKey: receivedKey) == nil {
            status = .denied
          } else { status = .granted }
        }
      }
    }
    return status
  }

  func requestAccess(
    completionHandler: @escaping (PrivateDataRequestAccessResult) -> Void
  ) {
    if CMMotionActivityManager.isActivityAvailable() == true {
      dataStore?.set("1", forKey: promptKey)
      activityManager.queryActivityStarting(
        from: Date(),
        to: Date(),
        to: activityQueue
      ) { [weak self] activities, error in guard let self = self else { return }
        if #available(iOS 11.0, *) {
          if self.accessLevel != self.currentPermissionState {
            self.currentPermissionState = self.accessLevel
            self.eventBus?.post(
              name: Constant.Notification.Activity.PermissionChangedEvent.name,
              userInfo: [
                Constant.Notification.Activity.PermissionChangedEvent.key: self
                  .accessLevel
              ]
            )
            guard let currentPermissionState = self.currentPermissionState
              else { return }
            self.dataStore?.set(
              currentPermissionState.rawValue,
              forKey: self.lastCurrentActivityPermissionKey
            )
          }
          completionHandler(
            PrivateDataRequestAccessResult(self.accessLevel)
          )
        } else {
          if activities != nil {
            self.dataStore?.set("1", forKey: self.receivedKey)
            completionHandler(
              PrivateDataRequestAccessResult(
                PrivateDataAccessLevel.granted
              )
            )
          } else if let error = error {
            self.dataStore?.removeObject(forKey: self.receivedKey)
            self.handleError(
              error as NSError,
              completionHandler: completionHandler
            )
          }
        }
      }
    } else {
      // hardware level not supported
      dataStore?.removeObject(forKey: receivedKey)
      completionHandler(PrivateDataRequestAccessResult(.unavailable))
    }
  }

  func checkPermissionStatus() {
    let status = accessLevel
    if status == .undetermined {
      eventBus?.post(
        name: Constant.Notification.Activity.PermissionChangedEvent.name,
        userInfo: [
          Constant.Notification.Activity.PermissionChangedEvent.key:
            PrivateDataAccessLevel.undetermined
        ]
      )
    } else {
      requestAccess { [weak self] result in
        guard let self = self else { return }
        if result.accessLevel != self.currentPermissionState {
          self.currentPermissionState = result.accessLevel
          self.eventBus?.post(
            name: Constant.Notification.Activity.PermissionChangedEvent.name,
            userInfo: [
              Constant.Notification.Activity.PermissionChangedEvent.key: result
                .accessLevel
            ]
          )
          guard let currentPermissionState = self.currentPermissionState else {
            return
          }
          self.dataStore?.set(
            currentPermissionState.rawValue,
            forKey: self.lastCurrentActivityPermissionKey
          )
        }
      }
    }
  }

  fileprivate func checkActivityPermission() {
    if accessLevel != currentPermissionState {
      self.currentPermissionState = accessLevel
      eventBus?.post(
        name: Constant.Notification.Activity.PermissionChangedEvent.name,
        userInfo: [
          Constant.Notification.Activity.PermissionChangedEvent.key: self
            .accessLevel
        ]
      )
      guard let currentPermissionState = self.currentPermissionState else {
        return
      }
      dataStore?.set(
        currentPermissionState.rawValue,
        forKey: lastCurrentActivityPermissionKey
      )
    }
  }

  fileprivate func handleError(
    _ error: NSError,
    completionHandler: @escaping (PrivateDataRequestAccessResult) -> Void
  ) {
    if error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
      completionHandler(
        PrivateDataRequestAccessResult(.denied, error: error)
      )
    } else {
      completionHandler(
        PrivateDataRequestAccessResult(.restricted, error: error)
      )
    }
  }
}
