import CoreLocation
import Foundation

final class Provider {
  /// Basic components
  static let eventBus: AbstractEventBus = EventBusWrapper().center

  static let fileStorage: AbstractFileStorage = FileStorage()
  static let appState: AbstractAppState = AppState(dataStore)
  static let errorHandler: AbstractErrorHandler = ErrorHandler(
    eventBus,
    dataStore
  )

  /// Services
  static let reachability: AbstractReachabilityManager = ReachabilityManager(
    configManager.config,
    eventBus
  )

  static let databaseManager: AbstractDatabaseManager = DatabaseManager(
    dbInput: DatabaseManager.Input(
      name: Constant.Database.name,
      collectionTypes: [.online, .custom]
    )
  )
  static let configManager: AbstractConfigManager = ConfigManager(fileStorage)
  static let dataStore: AbstractReadWriteDataStore = ReadWriteDataStoreWrapper(
    config: configManager.config
  ).defaults
  static let serviceManager: AbstractServiceManager = ServiceManager(
    configManager.config.services.types,
    configManager.config,
    eventBus,
    appState,
    collectionPipeline,
    ServiceFactory()
  )
  static let authManager: AuthTokenProvider = AuthManager(
    configManager.config,
    dataStore,
    serviceManager,
    eventBus,
    databaseManager,
    appState,
    errorHandler
  )
  static let apiClient: AbstractAPIClient = APIClient(
    configManager.config,
    authManager,
    appState
  )
  static let standbyChecker: StandbyChecker = StandbyChecker(
    configManager,
    eventBus,
    appState,
    apiClient,
    reachability,
    dataStore
  )

  /// Pipelines
  static let initPipeline: InitializationPipeline = InitializationPipeline(
    configManager.config,
    serviceManager,
    appState,
    eventBus,
    dataStore,
    authManager,
    reachability,
    errorHandler
  )

  static let collectionPipeline: AbstractCollectionPipeline =
    CollectionPipeline(
      CollectionPipeline.Input(
        config: configManager.config,
        eventBus: eventBus,
        databaseManager: databaseManager,
        appState: appState
      ),
      errorHandler
    )
  static let transmissionPipeline: AbstractTransmissionManager =
    TransmissionManager(
      TransmissionManager.Input(
        collectionTypes: [.online, .custom],
        config: configManager.config,
        eventBus: eventBus,
        databaseManager: databaseManager,
        apiClient: apiClient,
        appState: appState,
        sdkVersion: appState,
        reachability: reachability
      )
    )
  static let dispatch: AbstractDispatch = Dispatch(
    eventBus,
    configManager.config,
    DispatchStrategyContext(),
    transmissionPipeline
  )

  /// Remote Control
  static let silentNotificationReceiver: SilentNotificationReceiver =
    SilentNotificationReceiver(appState, eventBus, serviceManager, initPipeline)

  static let deviceSettings: AbstractSettings = DeviceSettings(
    appState,
    apiClient,
    eventBus,
    serviceManager,
    initPipeline
  )
}
