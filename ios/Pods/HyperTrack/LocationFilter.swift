import CoreLocation
import UIKit

final class LocationFilter {
  private var appState: ResumptionDateProtocol?
  private var currentActivityType: ActivityServiceData.ActivityType = .stop
  private var lastCoordinate: CLLocation?
  private var exponentialBackoff: Double

  init(appState: AbstractAppState?) {
    self.appState = appState
    exponentialBackoff =
      Constant.Config.Location.locationUpdateSettingForStop.time
  }

  func setActivity(_ type: ActivityServiceData.ActivityType) {
    currentActivityType = type
  }

  func rest() { lastCoordinate = nil }

  func filterСoordinates(current: [CLLocation]) -> [CLLocation] {
    logLocationFilter.log(
      "Filtering locations: \(current) with currentActivityType: \(currentActivityType)"
    )
    let actualLocations = current.filter {
      let currentDate = Date()
      let locationDate = $0.timestamp
      let locationTimeDelta = currentDate.timeIntervalSince(locationDate)
      let allowedTimeDelta = Constant.Config.Location.filterOutOldUpdatesTime

      if locationTimeDelta <= allowedTimeDelta {
        logLocationFilter.log(
          "Location's \($0) timestamp: \(locationDate) is within \(allowedTimeDelta) seconds window from currentDate: \(currentDate)"
        )
        return true
      } else {
        logLocationFilter.log(
          "Filtering out location: \($0) because its timestamp: \(locationDate) is \(locationTimeDelta) seconds in the past from currentDate: \(currentDate) while we only allow locations from \(allowedTimeDelta) seconds ago."
        )
        return false
      }
    }

    guard let currentCoordinate = actualLocations.last else { return [] }
    guard let previusCoordinate = lastCoordinate else {
      lastCoordinate = currentCoordinate
      return actualLocations
    }

    var deferredTime = previusCoordinate.timestamp
    var deferredDistance = 0.0

    switch currentActivityType {
      case .stop:
        deferredDistance =
          Constant.Config.Location.locationUpdateSettingForStop.distance
        deferredTime = deferredTime.addingTimeInterval(exponentialBackoff)
        if exponentialBackoff
          < Constant.Config.Location.locationUpdateSettingForStop.maxTime {
          exponentialBackoff +=
            Constant.Config.Location.locationUpdateSettingForStop.time
          logLocationFilter.log(
            "Setting exponentialBackoff: \(exponentialBackoff)"
          )
        }
      case .run:
        deferredDistance =
          Constant.Config.Location.locationUpdateSettingForRun.distance
        deferredTime = deferredTime.addingTimeInterval(
          Constant.Config.Location.locationUpdateSettingForRun.time
        )
        exponentialBackoff =
          Constant.Config.Location.locationUpdateSettingForStop.time
      case .cycle:
        deferredDistance =
          Constant.Config.Location.locationUpdateSettingForCycle.distance
        deferredTime = deferredTime.addingTimeInterval(
          Constant.Config.Location.locationUpdateSettingForCycle.time
        )
        exponentialBackoff =
          Constant.Config.Location.locationUpdateSettingForStop.time
      case .walk, .unsupported:
        deferredDistance =
          Constant.Config.Location.locationUpdateSettingForWalk.distance
        deferredTime = deferredTime.addingTimeInterval(
          Constant.Config.Location.locationUpdateSettingForWalk.time
        )
        exponentialBackoff =
          Constant.Config.Location.locationUpdateSettingForStop.time
      case .drive:
        deferredDistance =
          Constant.Config.Location.locationUpdateSettingForDrive.distance
        deferredTime = deferredTime.addingTimeInterval(
          Constant.Config.Location.locationUpdateSettingForDrive.time
        )
        exponentialBackoff =
          Constant.Config.Location.locationUpdateSettingForStop.time
    }

    let distanceDelta = previusCoordinate.distance(from: currentCoordinate)
    let isDistanceDeltaGraterThenFilter = distanceDelta >= deferredDistance

    let timeCurrent = currentCoordinate.timestamp
    let timeLastWithFilter = deferredTime
    let isTimeGreaterThenFilter = timeCurrent >= timeLastWithFilter

    let passedFilter = isDistanceDeltaGraterThenFilter
      && isTimeGreaterThenFilter
    let failedTime = isDistanceDeltaGraterThenFilter && !isTimeGreaterThenFilter
    let failedDistance = !isDistanceDeltaGraterThenFilter
      && isTimeGreaterThenFilter

    if passedFilter {
      logLocationFilter.log(
        "Location: \(currentCoordinate) passed distance filter where distanceDelta: \(distanceDelta) was greater or equal to distanceFilter: \(deferredDistance) and passed time filter with timeCurrent: \(timeCurrent) greater then or equal to timeLastWithFilter: \(timeLastWithFilter)"
      )
      lastCoordinate = currentCoordinate
      return [currentCoordinate]
    } else if failedTime {
      logLocationFilter.log(
        "Filtering out location: \(currentCoordinate) because it failed time filter where timeCurrent: \(timeCurrent) must be greater then or equal to timeLastWithFilter: \(timeLastWithFilter)"
      )
    } else if failedDistance {
      logLocationFilter.log(
        "Filtering out location: \(currentCoordinate) because it failed distance filter where distanceDelta: \(distanceDelta) needs to be greater or equal to distanceFilter: \(deferredDistance)"
      )
    } else {
      logLocationFilter.log(
        "Filtering out location: \(currentCoordinate) because it failed distance filter where distanceDelta: \(distanceDelta) needs to be greater or equal to distanceFilter: \(deferredDistance) and time filter where timeCurrent: \(timeCurrent) must be greater then or equal to timeLastWithFilter: \(timeLastWithFilter)"
      )
    }
    return []
  }
}
