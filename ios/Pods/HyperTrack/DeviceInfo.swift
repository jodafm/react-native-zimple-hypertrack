import CoreTelephony
import Foundation

protocol DeviceDataProtocol: AnyObject { func getDeviceData() -> DeviceInfo }

final class DeviceInfo: JSONDictProtocol, Codable {
  let deviceId: String
  let timeZone: String
  let networkOperator: String
  let deviceBrand: String
  let deviceModel: String
  let osName: String
  let osVersion: String
  let appPackageName: String
  let appVersion: String
  let sdkVersion: String
  let recordedAt: Date
  let hasPlayServices: String
  let deviceName: String?
  let osDeviceIdentifier: String
  let deviceMetaData: DeviceMetaData?
  let pushToken: String

  enum Keys: String, CodingKey {
    case deviceId
    case timeZone
    case networkOperator
    case deviceBrand
    case deviceModel
    case osName
    case osVersion
    case appPackageName
    case appVersion
    case sdkVersion
    case recordedAt
    case hasPlayServices
    case deviceName
    case osDeviceIdentifier
    case deviceMetaData
    case pushToken
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    deviceId = try container.decode(String.self, forKey: .deviceId)
    timeZone = try container.decode(String.self, forKey: .timeZone)
    networkOperator = try container.decode(
      String.self,
      forKey: .networkOperator
    )
    deviceBrand = try container.decode(String.self, forKey: .deviceBrand)
    deviceModel = try container.decode(String.self, forKey: .deviceModel)
    osName = try container.decode(String.self, forKey: .osName)
    osVersion = try container.decode(String.self, forKey: .osVersion)
    appPackageName = try container.decode(
      String.self,
      forKey: .appPackageName
    )
    appVersion = try container.decode(String.self, forKey: .appVersion)
    sdkVersion = try container.decode(String.self, forKey: .sdkVersion)
    recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    hasPlayServices = "false"
    deviceName = try container.decode(String.self, forKey: .deviceName)
    deviceMetaData = try container.decodeIfPresent(
      DeviceMetaData.self,
      forKey: .deviceMetaData
    )
    osDeviceIdentifier = try container.decode(
      String.self,
      forKey: .osDeviceIdentifier
    )
    pushToken = try container.decode(String.self, forKey: .pushToken)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(deviceId, forKey: .deviceId)
    try container.encode(timeZone, forKey: .timeZone)
    try container.encode(networkOperator, forKey: .networkOperator)
    try container.encode(deviceBrand, forKey: .deviceBrand)
    try container.encode(deviceModel, forKey: .deviceModel)
    try container.encode(osName, forKey: .osName)
    try container.encode(osVersion, forKey: .osVersion)
    try container.encode(appPackageName, forKey: .appPackageName)
    try container.encode(appVersion, forKey: .appVersion)
    try container.encode(sdkVersion, forKey: .sdkVersion)
    try container.encode(recordedAt, forKey: .recordedAt)
    try container.encode(hasPlayServices, forKey: .hasPlayServices)
    try container.encodeIfPresent(deviceMetaData, forKey: .deviceMetaData)
    try container.encode(deviceName, forKey: .deviceName)
    try container.encode(osDeviceIdentifier, forKey: .osDeviceIdentifier)
    try container.encode(pushToken, forKey: .pushToken)
  }

  init(
    osName: String,
    deviceId: String,
    timeZone: String,
    recordedAt: Date,
    osVersion: String,
    appVersion: String,
    sdkVersion: String,
    deviceName: String?,
    deviceBrand: String,
    deviceModel: String,
    appPackageName: String,
    networkOperator: String,
    osDeviceIdentifier: String,
    deviceMetaData: DeviceMetaData?,
    pushToken: String
  ) {
    self.deviceId = deviceId
    self.timeZone = timeZone
    self.networkOperator = networkOperator
    self.deviceBrand = deviceBrand
    self.deviceModel = deviceModel
    self.osName = osName
    self.osVersion = osVersion
    self.appPackageName = appPackageName
    self.appVersion = appVersion
    self.sdkVersion = sdkVersion
    self.recordedAt = recordedAt
    hasPlayServices = "false"
    self.deviceName = deviceName
    self.deviceMetaData = deviceMetaData
    self.osDeviceIdentifier = osDeviceIdentifier
    self.pushToken = pushToken
  }

  // MARK: JSON Result Protocol Method

  func jsonDict() -> JSONResult {
    var dict: [String: Any] = [:]
    dict[Constant.ServerKeys.DeviceInfo.deviceId] = deviceId
    dict[Constant.ServerKeys.DeviceInfo.timeZone] = timeZone
    dict[Constant.ServerKeys.DeviceInfo.networkOperator] = networkOperator
    dict[Constant.ServerKeys.DeviceInfo.deviceBrand] = deviceBrand
    dict[Constant.ServerKeys.DeviceInfo.deviceModel] = deviceModel
    dict[Constant.ServerKeys.DeviceInfo.osName] = osName
    dict[Constant.ServerKeys.DeviceInfo.osVersion] = osVersion
    dict[Constant.ServerKeys.DeviceInfo.appPackageName] = appPackageName
    dict[Constant.ServerKeys.DeviceInfo.appVersion] = appVersion
    dict[Constant.ServerKeys.DeviceInfo.sdkVersion] = sdkVersion
    dict[Constant.ServerKeys.DeviceInfo.hasPlayServices] = hasPlayServices
    dict[Constant.ServerKeys.DeviceInfo.recordedAt] = DateFormatter.iso8601Full
      .string(from: recordedAt)
    dict[Constant.ServerKeys.DeviceInfo.deviceName] = deviceName
    dict[Constant.ServerKeys.DeviceInfo.pushToken] = pushToken
    dict[Constant.ServerKeys.DeviceInfo.osDeviceIdentifier] = osDeviceIdentifier
    if let metaDict = deviceMetaData {
      do {
        let metaString = try String(
          data: JSONSerialization.data(withJSONObject: metaDict, options: []),
          encoding: .utf8
        ) ?? "{}"
        dict[Constant.ServerKeys.DeviceInfo.deviceMetaData] = metaString
      } catch {
        logGeneral.error(
          "Failed to serialize DeviceMetaData: \(metaDict) to JSON with error: \(error)"
        )
      }
    }
    return JSONResult.success(dict)
  }
}

extension DeviceInfo: Equatable {
  static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
    let lhsMetadata = lhs.deviceMetaData ?? [:]
    let rhsMetadata = rhs.deviceMetaData ?? [:]
    return (
      lhs.deviceId == rhs.deviceId && lhs.timeZone == rhs.timeZone
        && lhs.networkOperator == rhs.networkOperator
        && lhs.deviceBrand == rhs.deviceBrand
        && lhs.deviceModel == rhs.deviceModel && lhs.osName == rhs.osName
        && lhs.osVersion == rhs.osVersion
        && lhs.appPackageName == rhs.appPackageName
        && lhs.appVersion == rhs.appVersion && lhs.sdkVersion == rhs.sdkVersion
        && lhs.hasPlayServices == rhs.hasPlayServices
        && lhs.deviceName == rhs.deviceName
        && lhs.osDeviceIdentifier == rhs.osDeviceIdentifier
        && lhs.pushToken == rhs.pushToken && lhsMetadata == rhsMetadata
    )
  }
}
