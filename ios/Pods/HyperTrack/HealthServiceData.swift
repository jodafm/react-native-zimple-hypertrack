import Foundation

typealias HealthValues = (key: String, value: String, hint: String)
typealias TrackingState = (
  intent: UserTrackingState, permissions: Permissions,
  trackingStatus: TrackingStatus
)

struct HealthServiceData: AbstractServiceData {
  let healthId: String
  let recordedDate: Date
  var data: HealthData
  let healthKey: String

  init(healthType: HealthType, recordedDate: Date) {
    healthId = UUID().uuidString
    self.recordedDate = recordedDate
    data = HealthData(type: healthType)
    healthKey = healthType.healthValues().key
  }

  func getType() -> EventType { return EventType.healthChange }

  func getSortedKey() -> String { return healthKey }

  func getId() -> String { return healthId }

  func getRecordedAt() -> Date { return recordedDate }

  func getJSONdata() -> String {
    do {
      return try String(
        data: JSONEncoder.hyperTrackEncoder.encode(data),
        encoding: .utf8
      )!
    } catch { return "" }
  }
}

struct HealthData: Codable {
  let value: String
  let hint: String

  enum Keys: String, CodingKey {
    case value
    case hint
  }

  init(type: HealthType) {
    value = type.healthValues().value
    hint = type.healthValues().hint
  }
}

enum Permissions: Int {
  case denied
  case granted
}

enum TrackingStatus {
  case notTracking
  case tracking
}

enum TrackingReason: Int {
  case pushStart
  case pushStop
  case trackingStart
  case trackingStop
  case settingsStart
  case settingsStop
  case trialEnded

  func toString() -> String {
    switch self {
      case .pushStart: return "Push Start"
      case .pushStop: return "Push Stop"
      case .trackingStart: return "Tracking Start"
      case .trackingStop: return "Tracking Stop"
      case .settingsStart: return "Settings Start"
      case .settingsStop: return "Settings Stop"
      case .trialEnded: return "Trial ended"
    }
  }
}

enum SystemEvents {
  case trackingStopped
  case trackingStarted
  case permissionDenied
  case permissionGranted
  case unknown
}

enum HealthType: String {
  case trackingStopped = "tracking.stopped"
  case trackingStarted = "tracking.started"

  case trackingPushStopped = "tracking.push.stopped"
  case trackingPushStarted = "tracking.push.started"

  case trackingSettingsStopped = "settings.stop"
  case trackingSettingsStarted = "settings.start"

  case locationDisabled = "location.disabled"
  case locationPermissionDenied = "location.permission_denied"
  case locationPermissionGranted = "location.permission_granted"

  case activityDisabled = "activity.disabled"
  case activityUnavailable = "activity.not_supported"
  case activityPermissionDenied = "activity.permission_denied"
  case activityPermissionGranted = "activity.permission_granted"

  case batteryLow = "battery.low"
  case batteryNormal = "battery.back_to_normal"
  case batteryCharging = "battery.charging"
  case batteryDischarging = "battery.discharging"

  static func makeTrackingState(reason: TrackingReason?) -> (HealthType)? {
    guard let reason = reason else { return nil }
    switch reason {
      case .trackingStop: return .trackingStopped
      case .trackingStart: return .trackingStarted
      case .pushStart: return .trackingPushStarted
      case .pushStop: return .trackingPushStopped
      case .settingsStart: return .trackingPushStarted
      case .settingsStop: return .trackingPushStopped
      case .trialEnded: return nil
    }
  }

  func healthValues() -> (HealthValues) {
    switch self {
      case .trackingStopped:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.stopped,
          Constant.Health.Hint.Tracking.pause.rawValue
        )
      case .trackingStarted:
        return (
          Constant.Health.Value.Resumption.key,
          Constant.Health.Value.Resumption.started,
          Constant.Health.Hint.Tracking.resume.rawValue
        )

      case .trackingPushStopped:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.stopped,
          Constant.Health.Hint.Tracking.pushPause.rawValue
        )
      case .trackingPushStarted:
        return (
          Constant.Health.Value.Resumption.key,
          Constant.Health.Value.Resumption.started,
          Constant.Health.Hint.Tracking.pushResume.rawValue
        )

      case .trackingSettingsStopped:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.stopped,
          Constant.Health.Hint.Tracking.settingsPause.rawValue
        )
      case .trackingSettingsStarted:
        return (
          Constant.Health.Value.Resumption.key,
          Constant.Health.Value.Resumption.started,
          Constant.Health.Hint.Tracking.settingsResume.rawValue
        )

      case .locationDisabled:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.disabled,
          Constant.Health.Hint.LocationService.disabled.rawValue
        )
      case .locationPermissionDenied:
        return (
          Constant.Health.Value.Outage.key, Constant.Health.Value.Outage.denied,
          Constant.Health.Hint.LocationPermission.denied.rawValue
        )
      case .locationPermissionGranted:
        return (
          Constant.Health.Value.Resumption.key,
          Constant.Health.Value.Resumption.granted,
          Constant.Health.Hint.LocationPermission.granted.rawValue
        )

      case .activityUnavailable:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.disabled,
          Constant.Health.Hint.ActivityService.unavailable.rawValue
        )
      case .activityDisabled:
        return (
          Constant.Health.Value.Outage.key,
          Constant.Health.Value.Outage.disabled,
          Constant.Health.Hint.ActivityService.disabled.rawValue
        )
      case .activityPermissionDenied:
        return (
          Constant.Health.Value.Outage.key, Constant.Health.Value.Outage.denied,
          Constant.Health.Hint.ActivityPermission.denied.rawValue
        )
      case .activityPermissionGranted:
        return (
          Constant.Health.Value.Resumption.key,
          Constant.Health.Value.Resumption.granted,
          Constant.Health.Hint.ActivityPermission.granted.rawValue
        )

      case .batteryLow:
        return (
          Constant.Health.Key.batteryState,
          Constant.Health.Value.Status.update.rawValue,
          Constant.Health.Hint.BatteryLevel.low.rawValue
        )
      case .batteryNormal:
        return (
          Constant.Health.Key.batteryState,
          Constant.Health.Value.Status.update.rawValue,
          Constant.Health.Hint.BatteryLevel.normal.rawValue
        )
      case .batteryCharging:
        return (
          Constant.Health.Key.batteryState,
          Constant.Health.Value.Status.update.rawValue,
          Constant.Health.Hint.BatteryState.charging.rawValue
        )
      case .batteryDischarging:
        return (
          Constant.Health.Key.batteryState,
          Constant.Health.Value.Status.update.rawValue,
          Constant.Health.Hint.BatteryState.discharging.rawValue
        )
    }
  }

  func toSystemEvents() -> SystemEvents {
    switch self {
      case .trackingStopped, .trackingPushStopped, .trackingSettingsStopped:
        return .trackingStopped
      case .trackingStarted, .trackingPushStarted, .trackingSettingsStarted:
        return .trackingStarted
      case .locationDisabled, .locationPermissionDenied, .activityUnavailable,
           .activityDisabled, .activityPermissionDenied:
        return .permissionDenied
      case .locationPermissionGranted, .activityPermissionGranted:
        return .permissionGranted
      default: return .unknown
    }
  }
}
