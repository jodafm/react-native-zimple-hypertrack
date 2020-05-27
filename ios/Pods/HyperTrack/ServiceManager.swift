import Foundation

protocol BaseServiceManager: AnyObject {
  func startAllServices()
  func stopAllServices()
  func checkPermissions()
}

protocol AbstractServiceManager: AbstractServiceProtocol, BaseServiceManager {}

protocol AbstractServiceProtocol: AnyObject {
  func getService(_ serviceType: Config.Services.ServiceType)
    -> AbstractService?
  func startService(_ serviceType: Config.Services.ServiceType) throws
    -> ServiceError?
  func stopService(_ serviceType: Config.Services.ServiceType)
  func isServiceAuthorized(_ serviceType: Config.Services.ServiceType) -> Bool
  func isServiceRunning(_ serviceType: Config.Services.ServiceType) -> Bool
  func setEventUpdatesDelegate(
    _ delegate: EventUpdatesDelegate?,
    serviceType: Config.Services.ServiceType
  )
  func numberOfServices() -> Int
  func numberOfRunningServices() -> Int
  func checkPermission(_ serviceType: Config.Services.ServiceType)
}

final class ServiceManager: AbstractServiceManager {
  fileprivate var services: [Config.Services.ServiceType: AbstractService] = [:]
  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate weak var appState: AbstractAppState?

  fileprivate var canStartServices: Bool {
    return (
      appState?.userTrackingBehaviour == .resumed
        && appState?.getPublishableKey() != ""
    )
  }

  init(
    _ serviceTypes: [Config.Services.ServiceType],
    _ config: AbstractConfig?,
    _ eventBus: AbstractEventBus?,
    _ appState: AbstractAppState?,
    _ collection: AbstractCollectionPipeline?,
    _ factory: AbstractServiceFactory
  ) {
    self.eventBus = eventBus
    self.appState = appState
    serviceTypes.forEach {
      self.services[$0] = factory.getService(
        $0,
        config: config,
        collection: collection
      )
    }
    self.eventBus?.addObserver(
      self,
      selector: #selector(checkActivityPermission(_:)),
      name: Constant.Notification.Activity.PermissionChangedEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(checkLocationPermission(_:)),
      name: Constant.Notification.Location.PermissionChangedEvent.name
    )
  }

  func numberOfServices() -> Int {
    logService.log("Number of services: \(services.count)")
    return services.count
  }

  func numberOfRunningServices() -> Int {
    return services.filter { $0.value.isServiceRunning() }.count
  }

  func getService(_ serviceType: Config.Services.ServiceType)
    -> AbstractService?
  { return services[serviceType] }

  func startService(_ serviceType: Config.Services.ServiceType) throws
    -> ServiceError? {
    guard canStartServices else { return nil }
    do {
      _ = try services[serviceType]?.startService()
      logService.log("Started service: \(serviceType.description)")
      return nil
    } catch {
      logService.error(
        "Failed to start service: \(serviceType.description) with error: \(error)"
      )
      throw error
    }
  }

  func stopService(_ serviceType: Config.Services.ServiceType) {
    services[serviceType]?.stopService()
  }

  func checkPermission(_ serviceType: Config.Services.ServiceType) {
    services[serviceType]?.checkPermissionStatus()
    logService.debug(
      "Checking permissions for service: \(serviceType.description)"
    )
  }

  func checkPermissions() { services.forEach { checkPermission($0.key) } }

  func startAllServices() {
    guard services.filter({ !$0.value.isAuthorized() }).isEmpty else {
      return
    }
    services.forEach { do { _ = try startService($0.key) } catch {} }
  }

  func stopAllServices() { services.forEach { stopService($0.key) } }

  func isServiceAuthorized(_ serviceType: Config.Services.ServiceType) -> Bool {
    return services[serviceType]?.isAuthorized() ?? false
  }

  func isServiceRunning(_ serviceType: Config.Services.ServiceType) -> Bool {
    return services[serviceType]?.isServiceRunning() ?? false
  }

  func setEventUpdatesDelegate(
    _ delegate: EventUpdatesDelegate?,
    serviceType: Config.Services.ServiceType
  ) { services[serviceType]?.setEventUpdatesDelegate(delegate) }

  @objc private func checkLocationPermission(_ notif: Notification) {
    guard
      let accessLevel =
      notif.userInfo?[
        Constant.Notification.Location.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    servicesAccessControl(accessLevel)
  }

  @objc private func checkActivityPermission(_ notif: Notification) {
    guard
      let accessLevel =
      notif.userInfo?[
        Constant.Notification.Activity.PermissionChangedEvent.key
      ]
      as? PrivateDataAccessLevel
      else { return }
    servicesAccessControl(accessLevel)
  }

  private func servicesAccessControl(_ accessLevel: PrivateDataAccessLevel) {
    switch accessLevel {
      case .unavailable, .undetermined, .restricted, .denied: stopAllServices()
      case .granted, .grantedWhenInUse, .grantedAlways: startAllServices()
    }
  }
}

protocol AbstractServiceFactory {
  func getService(
    _ type: Config.Services.ServiceType,
    config: AbstractConfig?,
    collection: AbstractCollectionPipeline?
  ) -> AbstractService
}

final class ServiceFactory: AbstractServiceFactory {
  func getService(
    _ type: Config.Services.ServiceType,
    config: AbstractConfig?,
    collection: AbstractCollectionPipeline?
  ) -> AbstractService {
    switch type {
      case .location:
        return LocationService(
          config: config,
          locationManager: CoreLocationManager(
            config: config,
            eventBus: Provider.eventBus,
            locationFilter: LocationFilter(appState: Provider.appState),
            dataStore: Provider.dataStore
          ),
          collection: collection,
          eventBus: Provider.eventBus,
          appState: Provider.appState
        )
      case .activity:
        return ActivityService(
          withCollectionProtocol: collection,
          appState: Provider.appState,
          eventBus: Provider.eventBus,
          dataStore: Provider.dataStore
        )
      case .health:
        return HealthService(
          withCollectionProtocol: collection,
          eventBus: Provider.eventBus,
          dataStore: Provider.dataStore,
          healthBroadcastsReceiver: HealthBroadcastsReceiver(
            appState: Provider.appState,
            eventBus: Provider.eventBus,
            dataStore: Provider.dataStore,
            reachability: Provider.reachability
          )
        )
    }
  }
}
