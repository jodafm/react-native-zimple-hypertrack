import Foundation

protocol AbstractNetworkConfig: AnyObject {
  var network: Config.Network { get }
}

protocol AbstractDataStoreConfig: AnyObject {
  var dataStore: Config.DataStore { get }
}

protocol AbstractDispatchConfig: AnyObject {
  var dispatch: Config.Dispatch { get }
}

protocol AbstractTransmissionConfig: AbstractNetworkConfig {
  var transmission: Config.Transmission { get }
}

protocol AbstractLocationConfig: AnyObject {
  var location: Config.Location { get }
}

protocol AbstractCollectionConfig: AnyObject {
  var collection: Config.Collection { get }
}

protocol AbstractActivityConfig: AnyObject {
  var activity: Config.Activity { get }
}

protocol AbstractServicesConfig: AnyObject {
  var services: Config.Services { get }
}

protocol AbstractStandbyCheckerConfig: AnyObject {
  var standbyChecker: Config.StandbyChecker { get }
}

protocol AbstractConfig: AbstractDataStoreConfig, AbstractDispatchConfig,
  AbstractTransmissionConfig, AbstractLocationConfig, AbstractActivityConfig,
  AbstractServicesConfig, AbstractCollectionConfig, AbstractStandbyCheckerConfig
{}

protocol AbstractConfigManager {
  var config: Config { get }
  func updateConfig(_ config: Config)
  func updateConfig(filePath: String)
  func save()
}

final class ConfigManager: AbstractConfigManager {
  private(set) var config: Config
  fileprivate weak var storage: AbstractFileStorage?

  var fileName: String { return "\(Constant.namespace)\(Config.self).json" }

  init() { config = Config() }

  convenience init(_ storage: AbstractFileStorage?) {
    self.init()
    self.storage = storage
    guard
      let storedValues = storage?.retrieve(
        fileName,
        from: .documents,
        as: Config.self
      )
      else { return }
    config = storedValues
  }

  func save() { storage?.store(config, to: .documents, as: fileName) }

  func updateConfig(_ config: Config) { self.config.update(config) }

  func updateConfig(filePath: String) {
    guard let config = storage?.retrieve(filePath, as: Config.self) else {
      logGeneral.error(
        "Failed to update config from storage: \(String(describing: storage)) at filePath: \(filePath)"
      )
      return
    }
    self.config.update(config)
    save()
  }

  deinit { save() }
}

final class Config: NSObject, AbstractConfig, Codable {
  var network: Network
  var dataStore: DataStore
  var dispatch: Dispatch
  var transmission: Transmission
  var location: Location
  var activity: Activity
  var services: Services
  var collection: Collection
  var standbyChecker: StandbyChecker

  static var `default`: Config = Config()

  override init() {
    network = Network()
    dataStore = DataStore()
    dispatch = Dispatch()
    transmission = Transmission()
    location = Location()
    activity = Activity()
    services = Services()
    collection = Config.Collection()
    standbyChecker = Config.StandbyChecker()
    super.init()
  }

  func update(_ config: Config) {
    network = config.network
    dataStore = config.dataStore
    dispatch = config.dispatch
    transmission = config.transmission
    location = config.location
    activity = config.activity
    services = config.services
    collection = config.collection
    standbyChecker = config.standbyChecker
  }

  enum Keys: String, CodingKey {
    case network
    case dataStore
    case dispatch
    case transmission
    case location
    case activity
    case services
    case collection
    case standbyChecker
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    network = (try? container.decode(Network.self, forKey: .network))
      ?? Network()
    dataStore = (try? container.decode(DataStore.self, forKey: .dataStore))
      ?? DataStore()
    dispatch = (try? container.decode(Dispatch.self, forKey: .dispatch))
      ?? Dispatch()
    transmission = (
      try? container.decode(Transmission.self, forKey: .transmission)
    ) ?? Transmission()
    location = (try? container.decode(Location.self, forKey: .location))
      ?? Location()
    activity = (try? container.decode(Activity.self, forKey: .activity))
      ?? Activity()
    services = (try? container.decode(Services.self, forKey: .services))
      ?? Services()
    collection = (try? container.decode(Collection.self, forKey: .collection))
      ?? Collection()
    standbyChecker = (
      try? container.decode(StandbyChecker.self, forKey: .standbyChecker)
    ) ?? StandbyChecker()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(network, forKey: .network)
    try container.encode(dataStore, forKey: .dataStore)
    try container.encode(dispatch, forKey: .dispatch)
    try container.encode(transmission, forKey: .transmission)
    try container.encode(location, forKey: .location)
    try container.encode(activity, forKey: .activity)
    try container.encode(services, forKey: .services)
    try container.encode(collection, forKey: .collection)
    try container.encode(standbyChecker, forKey: .standbyChecker)
  }
}

extension Config {
  // MARK: - Internal classes

  struct Network: Codable {
    var timeoutInterval: Double
    var retryCount: Int
    var host: String
    var htBaseUrl: String
    var events: String
    var customEvents: String
    var registration: String
    var deviceSettings: String
    var authenticate: String

    init() {
      timeoutInterval = Constant.Config.Network.timeoutInterval
      retryCount = Constant.Config.Network.retryCount
      host = Constant.Config.Network.host
      htBaseUrl = Constant.Config.Network.htBaseUrl
      events = Constant.Config.Network.events
      customEvents = Constant.Config.Network.customEvents
      registration = Constant.Config.Network.registration
      deviceSettings = Constant.Config.Network.deviceSettings
      authenticate = Constant.Config.Network.authenticate
    }

    enum Keys: String, CodingKey {
      case timeoutInterval
      case retryCount
      case host
      case htBaseUrl
      case events
      case customEvents
      case registration
      case deviceSettings
      case authenticate
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      timeoutInterval = (
        try? container.decode(Double.self, forKey: .timeoutInterval)
      ) ?? Constant.Config.Network.timeoutInterval
      retryCount = (try? container.decode(Int.self, forKey: .retryCount))
        ?? Constant.Config.Network.retryCount
      host = (try? container.decode(String.self, forKey: .host))
        ?? Constant.Config.Network.host
      htBaseUrl = (try? container.decode(String.self, forKey: .htBaseUrl))
        ?? Constant.Config.Network.htBaseUrl
      events = (try? container.decode(String.self, forKey: .events))
        ?? Constant.Config.Network.events
      customEvents = (try? container.decode(String.self, forKey: .customEvents))
        ?? Constant.Config.Network.customEvents
      registration = (try? container.decode(String.self, forKey: .registration))
        ?? Constant.Config.Network.registration
      deviceSettings = (
        try? container.decode(String.self, forKey: .deviceSettings)
      ) ?? Constant.Config.Network.deviceSettings
      authenticate = (try? container.decode(String.self, forKey: .authenticate))
        ?? Constant.Config.Network.authenticate
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(timeoutInterval, forKey: .timeoutInterval)
      try container.encode(retryCount, forKey: .retryCount)
      try container.encode(host, forKey: .host)
      try container.encode(htBaseUrl, forKey: .htBaseUrl)
      try container.encode(events, forKey: .events)
      try container.encode(customEvents, forKey: .customEvents)
      try container.encode(registration, forKey: .registration)
      try container.encode(deviceSettings, forKey: .deviceSettings)
      try container.encode(authenticate, forKey: .authenticate)
    }
  }
}

extension Config {
  struct DataStore: Codable {
    var dataStoreSuitName: String

    init() { dataStoreSuitName = Constant.Config.DataStore.dataStoreSuitName }

    enum Keys: String, CodingKey { case dataStoreSuitName }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      dataStoreSuitName = (
        try? container.decode(String.self, forKey: .dataStoreSuitName)
      ) ?? Constant.Config.DataStore.dataStoreSuitName
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(dataStoreSuitName, forKey: .dataStoreSuitName)
    }
  }
}

extension Config {
  struct Dispatch: Codable {
    var frequency: Double
    let debounce: Double
    let throttle: Double
    var tolerance: Int
    var type: DispatchType

    init() {
      frequency = Constant.Config.Dispatch.frequency
      tolerance = Constant.Config.Dispatch.tolerance
      debounce = Constant.Config.Dispatch.debounce
      throttle = Constant.Config.Dispatch.throttle
      type = .timer
    }

    enum DispatchType: Int, Codable {
      case manual
      case timer
    }

    enum Keys: String, CodingKey {
      case frequency
      case tolerance
      case debounce
      case throttle
      case type
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      frequency = (try? container.decode(Double.self, forKey: .frequency))
        ?? Constant.Config.Dispatch.frequency
      tolerance = (try? container.decode(Int.self, forKey: .tolerance))
        ?? Constant.Config.Dispatch.tolerance
      debounce = (try? container.decode(Double.self, forKey: .debounce))
        ?? Constant.Config.Dispatch.debounce
      throttle = (try? container.decode(Double.self, forKey: .throttle))
        ?? Constant.Config.Dispatch.throttle
      type = (try? container.decode(DispatchType.self, forKey: .type)) ?? .timer
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(frequency, forKey: .frequency)
      try container.encode(tolerance, forKey: .tolerance)
      try container.encode(debounce, forKey: .debounce)
      try container.encode(throttle, forKey: .throttle)
      try container.encode(type, forKey: .type)
    }
  }
}

extension Config {
  struct Transmission: Codable {
    var batchSize: UInt

    init() { batchSize = Constant.Config.Transmission.batchSize }

    enum Keys: String, CodingKey { case batchSize }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      batchSize = (try? container.decode(UInt.self, forKey: .batchSize))
        ?? Constant.Config.Transmission.batchSize
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(batchSize, forKey: .batchSize)
    }
  }
}

extension Config {
  struct Location: Codable {
    var onlySignificantLocationUpdates: Bool
    var deferredLocationUpdatesDistance: Double
    var deferredLocationUpdatesTimeout: Double
    var backgroundLocationUpdates: Bool
    var distanceFilter: Double
    var desiredAccuracy: Double
    var permissionType: PermissionType
    var showsBackgroundLocationIndicator: Bool
    var pausesLocationUpdatesAutomatically: Bool

    enum PermissionType: Int, Codable {
      case always
      case whenInUse
    }

    init() {
      onlySignificantLocationUpdates =
        Constant.Config.Location.onlySignificantLocationUpdates
      deferredLocationUpdatesDistance =
        Constant.Config.Location.deferredLocationUpdatesDistance
      deferredLocationUpdatesTimeout =
        Constant.Config.Location.deferredLocationUpdatesTimeout
      backgroundLocationUpdates =
        Constant.Config.Location.backgroundLocationUpdates
      distanceFilter = Constant.Config.Location.distanceFilter
      desiredAccuracy = Constant.Config.Location.desiredAccuracy
      showsBackgroundLocationIndicator =
        Constant.Config.Location.showsBackgroundLocationIndicator
      permissionType = PermissionType(
        rawValue: Constant.Config.Location.permissionType
      ) ?? .always
      pausesLocationUpdatesAutomatically =
        Constant.Config.Location.pausesLocationUpdatesAutomatically
    }

    enum Keys: String, CodingKey {
      case onlySignificantLocationUpdates
      case deferredLocationUpdatesDistance
      case deferredLocationUpdatesTimeout
      case backgroundLocationUpdates
      case distanceFilter
      case desiredAccuracy
      case permissionType
      case showsBackgroundLocationIndicator
      case pausesLocationUpdatesAutomatically
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      onlySignificantLocationUpdates = (
        try? container.decode(
          Bool.self,
          forKey: .onlySignificantLocationUpdates
        )
      ) ?? Constant.Config.Location.onlySignificantLocationUpdates
      deferredLocationUpdatesDistance = (
        try? container.decode(
          Double.self,
          forKey: .deferredLocationUpdatesDistance
        )
      ) ?? Constant.Config.Location.deferredLocationUpdatesDistance
      deferredLocationUpdatesTimeout = (
        try? container.decode(
          Double.self,
          forKey: .deferredLocationUpdatesTimeout
        )
      ) ?? Constant.Config.Location.deferredLocationUpdatesTimeout
      backgroundLocationUpdates = (
        try? container.decode(Bool.self, forKey: .backgroundLocationUpdates)
      ) ?? Constant.Config.Location.backgroundLocationUpdates
      distanceFilter = (
        try? container.decode(Double.self, forKey: .distanceFilter)
      ) ?? Constant.Config.Location.distanceFilter
      desiredAccuracy = (
        try? container.decode(Double.self, forKey: .desiredAccuracy)
      ) ?? Constant.Config.Location.desiredAccuracy
      permissionType = (
        try? container.decode(PermissionType.self, forKey: .permissionType)
      ) ?? PermissionType(rawValue: Constant.Config.Location.permissionType)
        ?? .always
      showsBackgroundLocationIndicator = (
        try? container.decode(
          Bool.self,
          forKey: .showsBackgroundLocationIndicator
        )
      ) ?? Constant.Config.Location.showsBackgroundLocationIndicator
      pausesLocationUpdatesAutomatically = (
        try? container.decode(
          Bool.self,
          forKey: .pausesLocationUpdatesAutomatically
        )
      ) ?? Constant.Config.Location.pausesLocationUpdatesAutomatically
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(
        onlySignificantLocationUpdates,
        forKey: .onlySignificantLocationUpdates
      )
      try container.encode(
        deferredLocationUpdatesDistance,
        forKey: .deferredLocationUpdatesDistance
      )
      try container.encode(
        deferredLocationUpdatesTimeout,
        forKey: .deferredLocationUpdatesTimeout
      )
      try container.encode(
        backgroundLocationUpdates,
        forKey: .backgroundLocationUpdates
      )
      try container.encode(distanceFilter, forKey: .distanceFilter)
      try container.encode(desiredAccuracy, forKey: .desiredAccuracy)
      try container.encode(permissionType, forKey: .permissionType)
      try container.encode(
        showsBackgroundLocationIndicator,
        forKey: .showsBackgroundLocationIndicator
      )
      try container.encode(
        pausesLocationUpdatesAutomatically,
        forKey: .pausesLocationUpdatesAutomatically
      )
    }
  }
}

extension Config {
  struct StandbyChecker: Codable {
    var checkInterval: TimeInterval
    var toPing: Bool

    init() {
      checkInterval = Constant.Config.StandbyChecker.checkInterval
      toPing = Constant.Config.StandbyChecker.toPing
    }

    enum Keys: String, CodingKey {
      case checkInterval
      case toPing
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      checkInterval = (
        try? container.decode(TimeInterval.self, forKey: .checkInterval)
      ) ?? Constant.Config.StandbyChecker.checkInterval
      toPing = (try? container.decode(Bool.self, forKey: .toPing))
        ?? Constant.Config.StandbyChecker.toPing
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(checkInterval, forKey: .checkInterval)
      try container.encode(toPing, forKey: .toPing)
    }
  }
}

extension Config {
  struct Activity: Codable {
    var checkPermissionInterval: TimeInterval

    init() {
      checkPermissionInterval = Constant.Config.Activity.checkPermissionInterval
    }

    enum Keys: String, CodingKey { case checkPermissionInterval }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      checkPermissionInterval = (
        try? container.decode(
          TimeInterval.self,
          forKey: .checkPermissionInterval
        )
      ) ?? Constant.Config.Activity.checkPermissionInterval
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(
        checkPermissionInterval,
        forKey: .checkPermissionInterval
      )
    }
  }
}

extension Config {
  struct Services: Codable {
    var types: [ServiceType]

    init() {
      types = Constant.Config.Services.types.compactMap {
        ServiceType(rawValue: $0)
      }
    }

    @objc enum ServiceType: Int, Codable, CustomStringConvertible {
      case location
      case activity
      case health

      var description: String {
        switch self {
          case .location: return "location service"
          case .activity: return "activity service"
          case .health: return "health service"
        }
      }
    }

    enum Keys: String, CodingKey { case types }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      types = (try? container.decode([ServiceType].self, forKey: .types))
        ?? Constant.Config.Services.types.compactMap {
          ServiceType(rawValue: $0)
        }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(types, forKey: .types)
    }
  }
}

extension Config {
  struct Collection: Codable {
    var isFiltering: Bool

    init() { isFiltering = Constant.Config.Collection.isFiltering }

    enum Keys: String, CodingKey { case isFiltering }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Keys.self)
      isFiltering = (try? container.decode(Bool.self, forKey: .isFiltering))
        ?? Constant.Config.Collection.isFiltering
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: Keys.self)
      try container.encode(isFiltering, forKey: .isFiltering)
    }
  }
}
