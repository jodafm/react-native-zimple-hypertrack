import CoreLocation
import CoreMotion
import Foundation

struct ActivityServiceData: AbstractServiceData {
  let recordedDate: Date
  let osActivity: CMMotionActivity
  let activityId: String
  var data: ActivityData

  init(activityId: String, osActivity: CMMotionActivity, recordedDate: Date) {
    self.osActivity = osActivity
    self.activityId = activityId
    self.recordedDate = recordedDate
    data = ActivityData(
      value: ActivityServiceData.ActivityType(activity: osActivity)
    )
  }

  func getType() -> EventType { return getEventType() }

  func getRecordedAt() -> Date { return recordedDate }

  func getId() -> String { return activityId }

  func getSortedKey() -> String { return "" }

  func getJSONdata() -> String {
    do {
      return try String(
        data: JSONEncoder.hyperTrackEncoder.encode(data),
        encoding: .utf8
      )!
    } catch { return "" }
  }

  fileprivate func getEventType() -> EventType {
    return EventType.activityChange
  }

  enum ActivityType: String, Codable {
    case run
    case stop
    case walk
    case cycle
    case drive
    case unsupported

    var isSupported: Bool {
      switch self {
        case .unsupported: return false
        default: return true
      }
    }

    init(activity: CMMotionActivity) {
      if activity.walking { self = .walk } else if activity.running {
        self = .run
      } else if activity.automotive { self = .drive } else if activity.cycling {
        self = .cycle
      } else if activity.stationary { self = .stop } else {
        self = .unsupported
      }
    }
  }
}

struct ActivityData: Codable {
  let value: String
  var pedometer: StepsData?

  var type: ActivityServiceData.ActivityType? {
    return ActivityServiceData.ActivityType(rawValue: value)
  }

  init(value: ActivityServiceData.ActivityType) { self.value = value.rawValue }
}

struct StepsData: Codable {
  var timeDelta: Int // in nanoseconds.
  // Here 24 seconds lapsed from last steps data were received to time when activity occurred.
  // Negative values means that steps data update was received after activity transition was captured by system.
  var numberOfSteps: Int // steps walked since last steps data submission

  enum Keys: String, CodingKey {
    case timeDelta = "time_delta"
    case numberOfSteps = "number_of_steps"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(timeDelta, forKey: .timeDelta)
    try container.encode(numberOfSteps, forKey: .numberOfSteps)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    timeDelta = try container.decode(Int.self, forKey: .timeDelta)
    numberOfSteps = try container.decode(Int.self, forKey: .numberOfSteps)
  }

  init(timeDelta: Int, numberOfSteps: Int) {
    self.timeDelta = timeDelta
    self.numberOfSteps = numberOfSteps
  }
}
