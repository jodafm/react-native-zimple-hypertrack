import CoreLocation
import Foundation

struct LocationServiceData: AbstractServiceData, Codable {
  let id: String
  let data: LocationData
  let recordedAt: Date
  let type: String = EventType.locationChange.rawValue

  init(id: String, data: LocationData, recordedAt: Date) {
    self.id = id
    self.data = data
    self.recordedAt = recordedAt
  }

  static func getData(_ locations: [CLLocation]) -> [LocationServiceData] {
    var array: [LocationServiceData] = []
    locations.enumerated().forEach {
      let data = LocationData($0.element)
      array.append(
        LocationServiceData(
          id: UUID().uuidString,
          data: data,
          recordedAt: $0.element.timestamp
        )
      )
    }
    return array
  }

  func getType() -> EventType { return EventType.locationChange }

  func getSortedKey() -> String { return "" }

  func getId() -> String { return id }

  func getRecordedAt() -> Date { return recordedAt }

  func getJSONdata() -> String {
    do {
      return try String(
        data: JSONEncoder.hyperTrackEncoder.encode(data.toServer()),
        encoding: .utf8
      )!
    } catch { return "" }
  }

  enum Keys: String, CodingKey {
    case id
    case data
    case recordedAt = "recorded_at"
    case type
  }
}

struct LocationData: Codable {
  var speed: Double?
  var bearing: Double?
  let location: GeoJson
  var recorded_at: Date?
  let location_accuracy: Double

  init(_ location: CLLocation) {
    self.location = GeoJson(
      type: "Point",
      coordinates: location.coordinate,
      altitude: location.altitude
    )
    recorded_at = location.timestamp
    location_accuracy = location.horizontalAccuracy
    speed = location.speed
    bearing = location.course
  }

  func toServer() -> LocationData {
    var serverData = self

    // Checking Speed and Course
    if let bearing = self.bearing, bearing <= 0.0 { serverData.bearing = nil }
    if let speed = self.speed, speed <= 0.0 { serverData.speed = nil }
    serverData.recorded_at = nil

    return serverData
  }

  struct GeoJson: Codable {
    let type: String
    let coordinates: [Double]

    init(type: String, coordinates: CLLocationCoordinate2D, altitude: Double) {
      self.type = type
      self.coordinates = [coordinates.longitude.rounded(6), coordinates.latitude.rounded(6), altitude.rounded(2)]
    }
  }
}
