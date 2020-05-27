import CoreTelephony
import Foundation
import UIKit

func getBundle() -> Bundle? {
  let bundle = Bundle(for: HyperTrack.self)
  return bundle
}

func getSDKVersion() -> String {
  if let bundle = getBundle(), let dictionary = bundle.infoDictionary,
    let version = dictionary["CFBundleShortVersionString"] as? String
  { return version }
  return ""
}

typealias InitializedCompletionHandler = (InitializationState) -> Void
typealias DeviceMetaData = [String: Any]
typealias LastOnlineSessionInfo = (date: Date, isReachable: Bool)
typealias DeviceIdProtocol = GetDeviceIdProtocol
typealias SDKVersionProtocol = GetSDKVersionProtocol
typealias AccountDetailsProtocol = GetPublishableKeyProtocol
  & SetPublishableKeyProtocol & GetUserIdProtocol & SetUserIdProtocol
typealias AccountAndDeviceDetailsProvider = GetPublishableKeyProtocol
  & GetDeviceIdProtocol & GetUserIdProtocol & SetUserIdProtocol

protocol AbstractAppState: DeviceIdProtocol, SDKVersionProtocol,
  DeviceDataProtocol, AccountDetailsProtocol, ResumptionDateProtocol,
  CurrentSessionDeviceMetaDataProtocol, OnlineSessionInfoProtocol,
  PushNotificationDeviceTokenProtocol
{ var userTrackingBehaviour: UserTrackingState { get set } }

protocol GetSDKVersionProtocol: AnyObject { var sdkVersion: String { get } }

protocol GetDeviceIdProtocol: AnyObject { func getDeviceId() -> String }

protocol GetPublishableKeyProtocol: AnyObject {
  func getPublishableKey() -> String
}

protocol SetPublishableKeyProtocol { func setPublishableKey(_ id: String) }

protocol GetUserIdProtocol: AnyObject { func getUserId() -> String }

protocol SetUserIdProtocol { func setUserId(_ id: String) }

protocol CurrentSessionDeviceMetaDataProtocol {
  func saveCurrentSessionDevice(metaData: DeviceMetaData)
  func saveCurrentSessionDevice(name: String)
  func saveCurrentSessionDeviceInfo()
  var currentSessionDeviceName: String { get set }
  var currentSessionDeviceMetaData: DeviceMetaData? { get set }
  var currentSessionDeviceInfo: DeviceInfo? { get set }
}

protocol OnlineSessionInfoProtocol {
  func getLastOnlineSessionInfo() -> LastOnlineSessionInfo?
  func saveLastOnlineSession(info: LastOnlineSessionInfo)
}

protocol ResumptionDateProtocol { var resumptionDate: Date? { get set } }

protocol PushNotificationDeviceTokenProtocol {
  func getPushNotificationDeviceToken() -> String
  func savePushNotification(deviceToken: String)
}

enum InitializationState {
  case notInitialized
  case initialization
  case initialized
}

enum UserTrackingState: Int {
  case notRequested
  case paused
  case resumed
}

final class AppState: AbstractAppState {
  var sdkVersion: String = ""
  var currentSessionDeviceName: String
  var currentSessionDeviceMetaData: DeviceMetaData?
  var currentSessionDeviceInfo: DeviceInfo?

  fileprivate let userIdKey = "key.appState.userId"
  fileprivate let deviceIdKey = "key.appState.deviceId"
  fileprivate let deviceNameKey = "key.appState.deviceName"
  fileprivate let deviceInfoKey = "key.appState.deviceInfo"
  fileprivate let pausedByUserKey = "key.appState.pausedByUser"
  fileprivate let installationIdKey = "key.appState.installationId"
  fileprivate let deviceMetaDataKey = "key.appState.deviceMetaDataKey"
  fileprivate let resumptionDateKey = "key.appState.resumptionDateKey"
  fileprivate let publishableStoreKey = "key.appState.publishableStoreKey"
  fileprivate let lastOnlineSessionDateKey =
    "key.appState.lastonlinesessiondate"
  fileprivate let lastOnlineSessionReachableKey =
    "key.appState.lastonlinesessionreachable"
  fileprivate let pushNotificationDeviceTokenStoreKey =
    "key.appState.pushNotificationDeviceTokenStoreKey"
  fileprivate var userId: String
  fileprivate var deviceId: String
  fileprivate var publishableKey: String
  fileprivate let installationId: String
  fileprivate var pushNotificationDeviceToken: String
  fileprivate var lastOnlineSessionInfo: LastOnlineSessionInfo?
  fileprivate weak var dataStore: AbstractReadWriteDataStore?

  fileprivate static let isSimulator: Bool = {
    var isSim = false
    #if arch(i386) || arch(x86_64)
      isSim = true
    #endif
    return isSim
  }()

  var userTrackingBehaviour: UserTrackingState {
    get {
      guard let value = dataStore?.integer(forKey: pausedByUserKey) else {
        return .notRequested
      }
      return UserTrackingState(rawValue: value) ?? .notRequested
    }
    set { dataStore?.set(newValue.rawValue, forKey: pausedByUserKey) }
  }

  var resumptionDate: Date? {
    get { return dataStore?.object(forKey: resumptionDateKey) as? Date }
    set { dataStore?.set(newValue, forKey: resumptionDateKey) }
  }

  init(_ dataStore: AbstractReadWriteDataStore?) {
    self.dataStore = dataStore

    if let deviceId = dataStore?.string(forKey: deviceIdKey) {
      self.deviceId = deviceId
    } else {
      deviceId = UUID().uuidString
      dataStore?.set(deviceId, forKey: deviceIdKey)
    }

    if let installationId = dataStore?.string(forKey: installationIdKey) {
      self.installationId = installationId
    } else {
      installationId = UIDevice.current.identifierForVendor?.uuidString
        ?? UUID().uuidString
      dataStore?.set(installationId, forKey: installationIdKey)
    }

    if let userId = dataStore?.string(forKey: userIdKey) {
      self.userId = userId
    } else { userId = "" }

    publishableKey = ""
    currentSessionDeviceName = ""

    pushNotificationDeviceToken = ""
    let pushToken = getPushNotificationDeviceToken()
    if !pushToken.isEmpty { pushNotificationDeviceToken = pushToken } else
    { pushNotificationDeviceToken = "" }

    let savedDeviceDetails = getDeviceMetaData()

    if let deviceName = savedDeviceDetails.name, !deviceName.isEmpty {
      currentSessionDeviceName = deviceName
    } else { currentSessionDeviceName = UIDevice.current.name }

    if let deviceInfo = savedDeviceDetails.deviceInfo {
      currentSessionDeviceInfo = deviceInfo
    }

    currentSessionDeviceMetaData = savedDeviceDetails.metaData
    sdkVersion = getSDKVersion()

    if let lastOnlineSessionInfoValue = retrieveLastOnlineSessionInfo() {
      lastOnlineSessionInfo = lastOnlineSessionInfoValue
    }
  }

  func getUserId() -> String { return userId }

  func setUserId(_ id: String) {
    userId = id
    dataStore?.set(userId, forKey: userIdKey)
  }

  func getDeviceId() -> String { return deviceId }

  func getPublishableKey() -> String {
    if let savedPk = dataStore?.string(forKey: publishableStoreKey) {
      publishableKey = savedPk
      return publishableKey
    } else { return publishableKey }
  }

  func setPublishableKey(_ id: String) {
    publishableKey = id
    dataStore?.set(publishableKey, forKey: publishableStoreKey)
  }

  func getDeviceData() -> DeviceInfo {
    let deviceId = self.deviceId
    let timeZone = TimeZone.current.identifier
    let networkOprator =
      CTTelephonyNetworkInfo().subscriberCellularProvider?.carrierName
      ?? "unknown"
    let deviceBrand = "Apple"
    var deviceModel = UIDevice.fullModelName
    if AppState.isSimulator == true { deviceModel += " Simulator" }
    let osName = UIDevice.current.systemName
    let osVersion = UIDevice.current.systemVersion
    let appPackageName = Bundle.main.bundleIdentifier ?? ""
    var appVersion = ""
    let sdkVersion = getSDKVersion()
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
      as? String
    { appVersion = version }
    let deviceName = currentSessionDeviceName
    let deviceMetaData = currentSessionDeviceMetaData
    let pushToken = pushNotificationDeviceToken

    let deviceData = DeviceInfo(
      osName: osName,
      deviceId: deviceId,
      timeZone: timeZone,
      recordedAt: Date(),
      osVersion: osVersion,
      appVersion: appVersion,
      sdkVersion: sdkVersion,
      deviceName: deviceName,
      deviceBrand: deviceBrand,
      deviceModel: deviceModel,
      appPackageName: appPackageName,
      networkOperator: networkOprator,
      osDeviceIdentifier: installationId,
      deviceMetaData: deviceMetaData,
      pushToken: pushToken
    )
    return deviceData
  }

  fileprivate func retrieveLastOnlineSessionInfo() -> LastOnlineSessionInfo? {
    if let date = dataStore?.object(forKey: lastOnlineSessionDateKey) as? Date,
      let reachable = dataStore?.object(forKey: lastOnlineSessionReachableKey)
      as? Bool
    { return LastOnlineSessionInfo(date, reachable) }
    return nil
  }

  func getDeviceMetaData() -> (
    name: String?, metaData: [String: Any]?, deviceInfo: DeviceInfo?
  ) {
    let name = dataStore?.string(forKey: deviceNameKey)
    let metaData = dataStore?.object(forKey: deviceMetaDataKey)
      as? [String: Any]
    let data = dataStore?.object(forKey: deviceInfoKey) as? Data
    var deviceInfo: DeviceInfo?
    if let data = data,
      let decodedDeviceInfo = try? PropertyListDecoder().decode(
        DeviceInfo.self,
        from: data
      )
    { deviceInfo = decodedDeviceInfo }
    return (name, metaData, deviceInfo)
  }

  func saveCurrentSessionDevice(metaData: DeviceMetaData) {
    currentSessionDeviceMetaData = metaData
    dataStore?.set(currentSessionDeviceMetaData, forKey: deviceMetaDataKey)
  }

  func saveCurrentSessionDevice(name: String) {
    currentSessionDeviceName = name
    dataStore?.set(currentSessionDeviceName, forKey: deviceNameKey)
  }

  func saveCurrentSessionDeviceInfo() {
    guard let currentSessionDeviceInfo = currentSessionDeviceInfo else {
      return
    }
    dataStore?.set(
      try? PropertyListEncoder().encode(currentSessionDeviceInfo),
      forKey: deviceInfoKey
    )
  }

  func getLastOnlineSessionInfo() -> LastOnlineSessionInfo? {
    return lastOnlineSessionInfo
  }

  func saveLastOnlineSession(info: LastOnlineSessionInfo) {
    lastOnlineSessionInfo = info
    dataStore?.set(info.date, forKey: lastOnlineSessionDateKey)
    dataStore?.set(info.isReachable, forKey: lastOnlineSessionReachableKey)
  }

  func getPushNotificationDeviceToken() -> String {
    if let token = dataStore?.string(
      forKey: pushNotificationDeviceTokenStoreKey
    ) { return token }
    return ""
  }

  func savePushNotification(deviceToken: String) {
    pushNotificationDeviceToken = deviceToken
    dataStore?.set(deviceToken, forKey: pushNotificationDeviceTokenStoreKey)
  }

  func saveResumption(_ date: Date) {
    resumptionDate = date
    dataStore?.set(resumptionDate, forKey: resumptionDateKey)
  }
}
