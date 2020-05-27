import Foundation

protocol AbstractReadDataStore {
  func object(forKey defaultName: String) -> Any?
  func string(forKey defaultName: String) -> String?
  func array(forKey defaultName: String) -> [Any]?
  func dictionary(forKey defaultName: String) -> [String: Any]?
  func data(forKey defaultName: String) -> Data?
  func stringArray(forKey defaultName: String) -> [String]?
  func integer(forKey defaultName: String) -> Int
  func float(forKey defaultName: String) -> Float
  func double(forKey defaultName: String) -> Double
  func bool(forKey defaultName: String) -> Bool
}

protocol AbstractWriteDataStore {
  func set(_ value: Any?, forKey defaultName: String)
  func removeObject(forKey defaultName: String)
  func deleteAllValues()
}

protocol AbstractReadWriteDataStore: AnyObject, AbstractReadDataStore,
  AbstractWriteDataStore
{}

final class ReadWriteDataStoreWrapper {
  lazy var defaults: AbstractReadWriteDataStore = {
    SDKUserDefaults(config: config)
  }()

  private weak var config: AbstractDataStoreConfig?

  init(config: AbstractDataStoreConfig) { self.config = config }
}

final class SDKUserDefaults: AbstractReadWriteDataStore {
  private var suiteName: String {
    return config?.dataStore.dataStoreSuitName
      ?? Constant.Config.DataStore.dataStoreSuitName
  }

  private var defaults: UserDefaults?
  fileprivate weak var config: AbstractDataStoreConfig?

  convenience init(config: AbstractDataStoreConfig?) {
    self.init()
    self.config = config
    if defaults == nil {
      logDefaults.error(
        "Failed to construct SDKUserDefaults with suiteName: \(suiteName)"
      )
    }
  }

  init() { defaults = UserDefaults(suiteName: suiteName) }
}

extension SDKUserDefaults: AbstractReadDataStore {
  func object(forKey defaultName: String) -> Any? {
    return defaults?.object(forKey: defaultName)
  }

  func string(forKey defaultName: String) -> String? {
    return defaults?.string(forKey: defaultName)
  }

  func array(forKey defaultName: String) -> [Any]? {
    return defaults?.array(forKey: defaultName)
  }

  func dictionary(forKey defaultName: String) -> [String: Any]? {
    return defaults?.dictionary(forKey: defaultName)
  }

  func data(forKey defaultName: String) -> Data? {
    return defaults?.data(forKey: defaultName)
  }

  func stringArray(forKey defaultName: String) -> [String]? {
    return defaults?.stringArray(forKey: defaultName)
  }

  func integer(forKey defaultName: String) -> Int {
    return defaults?.integer(forKey: defaultName) ?? 0
  }

  func float(forKey defaultName: String) -> Float {
    return defaults?.float(forKey: defaultName) ?? 0
  }

  func double(forKey defaultName: String) -> Double {
    return defaults?.double(forKey: defaultName) ?? 0
  }

  func bool(forKey defaultName: String) -> Bool {
    return defaults?.bool(forKey: defaultName) ?? false
  }

  func url(forKey defaultName: String) -> URL? {
    return defaults?.url(forKey: defaultName)
  }
}

extension SDKUserDefaults: AbstractWriteDataStore {
  func set(_ value: Any?, forKey defaultName: String) {
    defaults?.set(value, forKey: defaultName)
  }

  func removeObject(forKey defaultName: String) {
    defaults?.removeObject(forKey: defaultName)
  }

  func deleteAllValues() {
    defaults?.removePersistentDomain(forName: suiteName)
  }
}
