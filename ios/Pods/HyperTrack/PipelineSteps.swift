import CoreLocation
import Foundation

protocol BaseAbstractPipeline: PipelineLogging {
  var isExecuting: Bool { get set }
}

protocol AbstractPipeline: BaseAbstractPipeline {
  func execute(completionHandler: ((SDKError?) -> Void)?)
}

protocol InitializeAbstractPipeline: BaseAbstractPipeline {
  func execute(
    for reason: TrackingReason,
    completionHandler: ((SDKError?) -> Void)?
  )
}

extension BaseAbstractPipeline {
  func setState(
    _ type: Pipeline.State,
    file _: StaticString = #file,
    function _: StaticString = #function,
    line _: UInt = #line
  ) { isExecuting = type.isExecuting }
}

protocol PipelineLogging: AnyObject { var context: Int { get } }

extension PipelineLogging {
  func log(
    _ type: Pipeline.State,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) {
    let className = String(describing: Self.self)
    switch type {
      case .executing:
        logPipeline.debug(
          "Executing \(className)",
          file: file,
          function: function,
          line: line
        )
      case let .failure(error):
        logPipeline.error(
          "Failed to execute \(className) because \(error.coreErrorDescription)",
          file: file,
          function: function,
          line: line
        )
      case .success:
        logPipeline.debug(
          "Executed \(className)",
          file: file,
          function: function,
          line: line
        )
    }
  }
}

class AbstractPipelineStep<Input, Output>: PipelineLogging {
  var context: Int { return Constant.Context.pipelineStep }

  func execute(input _: Input) -> Task<Output> { return Task<Output>() }

  func setState(
    _ type: Pipeline.State,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) { log(type, file: file, function: function, line: line) }
}

protocol TransmissionDatabaseStepInput {
  var batchSize: UInt { get }
  var config: AbstractTransmissionConfig? { get }
  var database: EventsTableManager? { get }
}

protocol TransmissionNetworkStepInput {
  var config: AbstractNetworkConfig? { get }
  var apiClient: AbstractAPIClient? { get }
  var deviceID: GetDeviceIdProtocol? { get }
}

enum Transmission {
  enum Input {
    struct Database: TransmissionDatabaseStepInput {
      let batchSize: UInt
      let config: AbstractTransmissionConfig?
      let database: EventsTableManager?
    }

    struct Network: TransmissionNetworkStepInput {
      let config: AbstractNetworkConfig?
      let apiClient: AbstractAPIClient?
      let deviceID: GetDeviceIdProtocol?
    }
  }
}

protocol ReAuthorizeStepInput {
  var tokenProvider: AuthTokenProvider? { get }
  var apiClient: AbstractAPIClient? { get }
  var detailsProvider: AccountAndDeviceDetailsProvider? { get }
}

enum Initialization {
  enum Input {
    struct ReAuthorize: ReAuthorizeStepInput {
      let tokenProvider: AuthTokenProvider?
      let apiClient: AbstractAPIClient?
      let detailsProvider: AccountAndDeviceDetailsProvider?
    }
  }
}

enum Pipeline {
  enum Collection {
    enum Input {
      struct DatabaseWrite {
        let events: [Event]
        let database: EventsTableManager?
      }
    }
  }

  enum Transmission {
    enum Input {
      struct ReadDatabase {
        let deviceId: String
        let sdkVersion: String
      }

      struct Mapper {
        let events: [Event]
        let deviceId: String
        let sdkVersion: String
      }

      struct Network {
        let events: [Event]
        let payload: [Payload]
      }

      struct WriteDatabase {
        let events: [Event]
        let response: Response
      }

      struct PipelineEnded { let events: [Event] }
    }
  }

  enum State {
    case executing
    case failure(Error)
    case success

    var isExecuting: Bool {
      switch self {
        case .executing: return true
        default: return false
      }
    }
  }
}

final class ReachabilityStep: AbstractPipelineStep<Void, Bool> {
  weak var reachability: AbstractReachabilityManager?

  init(reachability: AbstractReachabilityManager?) {
    self.reachability = reachability
  }

  override func execute(input _: Void) -> Task<Bool> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Bool>()
    guard let reachability = reachability, reachability.isReachable else {
      let error = SDKError(.networkDisconnected)
      taskSource.set(error: error)
      setState(.failure(error))
      return taskSource.task
    }
    taskSource.set(result: reachability.isReachable)
    setState(.success)
    return taskSource.task
  }
}

final class TransmissionReadDatabaseStep: AbstractPipelineStep<
  Pipeline.Transmission.Input.ReadDatabase, Pipeline.Transmission.Input.Mapper
>, TransmissionDatabaseStepInput {
  weak var config: AbstractTransmissionConfig?
  weak var database: EventsTableManager?
  let batchSize: UInt

  init(input: TransmissionDatabaseStepInput) {
    config = input.config
    database = input.database
    batchSize = input.batchSize
    super.init()
  }

  override func execute(input: Pipeline.Transmission.Input.ReadDatabase)
    -> Task<Pipeline.Transmission.Input.Mapper> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Pipeline.Transmission.Input.Mapper>()

    database?.fetch(
      count: batchSize,
      result: { [weak self] result in
        switch result {
          case let .success(events):
            if !events.isEmpty {
              taskSource.set(
                result: Pipeline.Transmission.Input.Mapper(
                  events: events,
                  deviceId: input.deviceId,
                  sdkVersion: input.sdkVersion
                )
              )
            } else {
              let error = SDKError(.emptyResult)
              taskSource.set(error: error)
            }
            self?.setState(.success)
          case .failure:
            let error = SDKError(.databaseReadFailed)
            taskSource.set(error: error)
            self?.setState(.failure(error))
        }
      }
    )
    return taskSource.task
  }
}

final class TransmissionEventMapper: AbstractPipelineStep<
  Pipeline.Transmission.Input.Mapper, Pipeline.Transmission.Input.Network
> {
  override init() {}

  override func execute(input: Pipeline.Transmission.Input.Mapper) -> Task<
    Pipeline.Transmission.Input.Network
  > {
    setState(.executing)
    let taskSource = TaskCompletionSource<Pipeline.Transmission.Input.Network>()
    let events = input.events.compactMap { (event) -> Payload? in
      var params: Payload!
      switch event.jsonDict() {
        case let .success(eventDict):
          params = eventDict
          params[Constant.ServerKeys.Event.deviceId] = input.deviceId
          params[Constant.ServerKeys.Event.source] = [
            Constant.ServerKeys.Event.sdkVersion: "iOS \(input.sdkVersion)"
          ]
          return params
        case .failure: return nil
      }
    }
    taskSource.set(
      result: Pipeline.Transmission.Input.Network(
        events: input.events,
        payload: events
      )
    )
    setState(.success)
    return taskSource.task
  }
}

final class TransmissionEventNetworkStep: AbstractPipelineStep<
  Pipeline.Transmission.Input.Network, Pipeline.Transmission.Input.WriteDatabase
>, TransmissionNetworkStepInput {
  weak var config: AbstractNetworkConfig?
  weak var apiClient: AbstractAPIClient?
  weak var deviceID: GetDeviceIdProtocol?

  init(input: TransmissionNetworkStepInput) {
    config = input.config
    apiClient = input.apiClient
    deviceID = input.deviceID
    super.init()
  }

  override func execute(input: Pipeline.Transmission.Input.Network) -> Task<
    Pipeline.Transmission.Input.WriteDatabase
  > {
    setState(.executing)
    let taskSource = TaskCompletionSource<
      Pipeline.Transmission.Input.WriteDatabase
    >()
    guard let apiClient = apiClient else {
      let error = SDKError(.unknown)
      taskSource.set(error: error)
      setState(.failure(error))
      return taskSource.task
    }
    apiClient.makeRequest(ApiRouter.sendEvent(input.payload)).continueWith(
      continuation: { [weak self] (task) -> Void in
        if let error = task.error {
          taskSource.set(error: error)
          self?.setState(.failure(error))
        } else if let result = task.result {
          taskSource.set(
            result: Pipeline.Transmission.Input.WriteDatabase(
              events: input.events,
              response: result
            )
          )
          self?.setState(.success)
        } else {
          let error = SDKError(.unknown)
          taskSource.set(error: error)
          self?.setState(.failure(error))
        }
      }
    )
    return taskSource.task
  }
}

final class TransmissionCustomEventNetworkStep: AbstractPipelineStep<
  Pipeline.Transmission.Input.Network, Pipeline.Transmission.Input.WriteDatabase
>, TransmissionNetworkStepInput {
  weak var config: AbstractNetworkConfig?
  weak var apiClient: AbstractAPIClient?
  weak var deviceID: GetDeviceIdProtocol?

  init(input: TransmissionNetworkStepInput) {
    config = input.config
    apiClient = input.apiClient
    deviceID = input.deviceID
    super.init()
  }

  override func execute(input: Pipeline.Transmission.Input.Network) -> Task<
    Pipeline.Transmission.Input.WriteDatabase
  > {
    setState(.executing)
    let taskSource = TaskCompletionSource<
      Pipeline.Transmission.Input.WriteDatabase
    >()
    guard let apiClient = apiClient, let deviceId = deviceID?.getDeviceId()
      else {
        let error = SDKError(.unknown)
        taskSource.set(error: error)
        setState(.failure(error))
        return taskSource.task
    }
    apiClient.makeRequest(ApiRouter.sendCustomEvent(deviceId, input.payload))
      .continueWith(continuation: { [weak self] (task) -> Void in
        if let error = task.error {
          taskSource.set(error: error)
          self?.setState(.failure(error))
        } else if let result = task.result {
          taskSource.set(
            result: Pipeline.Transmission.Input.WriteDatabase(
              events: input.events,
              response: result
            )
          )
          self?.setState(.success)
        } else {
          let error = SDKError(.unknown)
          taskSource.set(error: error)
          self?.setState(.failure(error))
        }
      })
    return taskSource.task
  }
}

final class TransmissionWriteDatabaseStep: AbstractPipelineStep<
  Pipeline.Transmission.Input.WriteDatabase,
  Pipeline.Transmission.Input.PipelineEnded
>, TransmissionDatabaseStepInput {
  var batchSize: UInt = 0
  weak var config: AbstractTransmissionConfig?
  weak var database: EventsTableManager?

  init(input: TransmissionDatabaseStepInput) {
    config = input.config
    database = input.database
    super.init()
  }

  override func execute(input: Pipeline.Transmission.Input.WriteDatabase)
    -> Task<Pipeline.Transmission.Input.PipelineEnded> {
    setState(.executing)
    let taskSource = TaskCompletionSource<
      Pipeline.Transmission.Input.PipelineEnded
    >()
    if let error = input.response.error {
      taskSource.set(error: error)
      setState(.failure(error))
    } else {
      database?.delete(
        items: input.events,
        result: { [weak self] result in
          switch result {
            case .success:
              taskSource.set(
                result: Pipeline.Transmission.Input.PipelineEnded(
                  events: input.events
                )
              )
              self?.setState(.success)
            case .failure:
              let error = SDKError(.databaseWriteFailed)
              taskSource.set(error: error)
              self?.setState(.failure(error))
          }
        }
      )
    }
    return taskSource.task
  }
}

final class PermissionStep: AbstractPipelineStep<Void, Bool> {
  fileprivate weak var serviceManager: AbstractServiceManager?

  init(serviceManager: AbstractServiceManager?) {
    self.serviceManager = serviceManager
  }

  override func execute(input _: Void) -> Task<Bool> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Bool>()
    guard let serviceManager = self.serviceManager else {
      taskSource.set(error: SDKError(.unknownService))
      return taskSource.task
    }
    if let locationService = serviceManager.getService(.location)
      as? AbstractLocationService,
      let activityService = serviceManager.getService(.activity)
      as? PrivateDataAccessProvider {
      locationService.requestPermissions { [weak self] locationAuthStatus in
        guard let self = self else {
          taskSource.set(error: SDKError(.unknownService))
          return
        }
        activityService.requestAccess(completionHandler: {
          [weak self] result in
          guard let self = self else {
            taskSource.set(error: SDKError(.unknownService))
            return
          }
          if taskSource.task.completed { return }
          if !CLLocationManager.locationServicesEnabled() {
            let error = SDKError(.locationServicesDisabled)
            taskSource.set(error: error)
            self.setState(.failure(error))
          } else if locationAuthStatus == .denied {
            let error = SDKError(.locationPermissionsDenied)
            taskSource.set(error: error)
            self.setState(.failure(error))
          } else {
            switch result.accessLevel {
              case .granted, .grantedAlways, .grantedWhenInUse:
                taskSource.set(result: true)
                self.setState(.success)
              case .restricted:
                let error = SDKError(.activityServicesDisabled)
                taskSource.set(error: error)
                self.setState(.failure(error))
              case .denied:
                let error = SDKError(.activityPermissionsDenied)
                taskSource.set(error: error)
                self.setState(.failure(error))
              default:
                let error = SDKError(.unknownService)
                taskSource.set(error: error)
                self.setState(.failure(error))
            }
          }
        })
      }
    } else {
      let error = SDKError(.unknownService)
      taskSource.set(error: error)
      setState(.failure(error))
    }
    return taskSource.task
  }
}

final class CollectionWriteDataBaseEntity: AbstractPipelineStep<
  Pipeline.Collection.Input.DatabaseWrite, Bool
> {
  fileprivate weak var config: AbstractCollectionConfig?

  init(config: AbstractCollectionConfig?) {
    self.config = config
    super.init()
  }

  override func execute(input: Pipeline.Collection.Input.DatabaseWrite) -> Task<
    Bool
  > {
    setState(.executing)
    let taskSource = TaskCompletionSource<Bool>()
    input.database?.insert(
      items: input.events,
      result: { [weak self] result in
        switch result {
          case .success:
            taskSource.set(result: true)
            self?.setState(.success)
          case .failure:
            let error = SDKError(.databaseWriteFailed)
            taskSource.set(error: error)
            self?.setState(.failure(error))
        }
      }
    )
    return taskSource.task
  }
}

final class CollectionMappingEntity: AbstractPipelineStep<
  [AbstractServiceData], [Event]
> {
  override func execute(input: [AbstractServiceData]) -> Task<[Event]> {
    setState(.executing)
    let taskSource = TaskCompletionSource<[Event]>()
    let events = input.map {
      Event(
        type: $0.getType(),
        sortedKey: $0.getSortedKey(),
        data: $0.getJSONdata(),
        id: $0.getId(),
        recordedAt: DateFormatter.iso8601Full.string(from: $0.getRecordedAt())
      )
    }
    if !events.isEmpty {
      taskSource.set(result: events)
      setState(.success)
    } else {
      let error = SDKError(.sensorToDataMappingFailed)
      taskSource.set(error: error)
      setState(.failure(error))
    }
    return taskSource.task
  }
}

final class CheckAuthorizationTokenStep: AbstractPipelineStep<Void, Bool> {
  fileprivate var reauthStep: ReAuthorizeStep

  init(input: ReAuthorizeStepInput) {
    reauthStep = ReAuthorizeStep(input: input)
    super.init()
  }

  override func execute(input _: Void) -> Task<Bool> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Bool>()
    if let token = reauthStep.tokenProvider?.authToken?.token, token != "" {
      taskSource.set(result: true)
    } else {
      reauthStep.execute(input: ()).continueWith { [weak self] task in
        if let error = task.error {
          taskSource.set(error: error)
          self?.setState(.failure(error))
        } else {
          taskSource.set(result: true)
          self?.setState(.success)
        }
      }
    }
    return taskSource.task
  }
}

final class ReAuthorizeStep: AbstractPipelineStep<Void, Response>,
  ReAuthorizeStepInput {
  weak var tokenProvider: AuthTokenProvider?
  weak var apiClient: AbstractAPIClient?
  weak var detailsProvider: AccountAndDeviceDetailsProvider?

  init(input: ReAuthorizeStepInput) {
    tokenProvider = input.tokenProvider
    apiClient = input.apiClient
    detailsProvider = input.detailsProvider
    super.init()
  }

  override func execute(input _: Void) -> Task<Response> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Response>()
    guard let apiClient = apiClient,
      let deviceId = detailsProvider?.getDeviceId()
      else {
        let error = SDKError(.deviceIdBlank)
        taskSource.set(error: error)
        setState(.failure(error))
        return taskSource.task
    }
    apiClient.makeRequest(ApiRouter.getToken(deviceId: deviceId)).continueWith(
      continuation: { [weak self] (task) -> Void in
        if let error = task.error {
          self?.setState(.failure(error))
          taskSource.set(error: error)
        } else if let result = task.result, let data = result.data {
          let authToken = try JSONDecoder.hyperTrackDecoder.decode(
            AuthToken.self,
            from: data
          )
          self?.tokenProvider?.authToken = authToken
          self?.tokenProvider?.status = .active
          taskSource.set(result: result)
          self?.setState(.success)
        } else {
          let error = SDKError(.unknown)
          taskSource.set(error: error)
          self?.setState(.failure(error))
        }
      }
    )
    return taskSource.task
  }
}

final class InitDeviceRegistrationEntity: AbstractPipelineStep<Void, Bool> {
  fileprivate weak var apiClient: AbstractAPIClient?
  fileprivate weak var appState: AbstractAppState?

  init(apiClient: AbstractAPIClient?, appState: AbstractAppState?) {
    self.apiClient = apiClient
    self.appState = appState
    super.init()
  }

  override func execute(input _: Void) -> Task<Bool> {
    setState(.executing)
    let taskSource = TaskCompletionSource<Bool>()
    let userIdKey = "user_id"
    guard let apiClient = apiClient, var appState = appState else {
      let error = SDKError(.unknown)
      taskSource.set(error: error)
      setState(.failure(error))
      return taskSource.task
    }

    var payload: Payload?
    var deviceInfo: DeviceInfo?
    switch appState.getDeviceData().jsonDict() {
      case let .success(dict):
        payload = dict
        deviceInfo = appState.getDeviceData()
      case .failure:
        let error = SDKError(.unknown)
        taskSource.set(error: error)
        setState(.failure(error))
    }
    if let payload = payload, deviceInfo != appState.currentSessionDeviceInfo {
      apiClient.makeRequest(
        ApiRouter.deviceRegister(appState.getDeviceId(), payload)
      ).continueWith { [weak self] (task) -> Void in
        guard let self = self else { return }
        if let error = task.error {
          taskSource.set(error: error)
          self.setState(.failure(error))
        } else if let result = task.result, let data = result.data {
          do {
            if let dict = try JSONSerialization.jsonObject(
              with: data,
              options: JSONSerialization.ReadingOptions.allowFragments
            ) as? [String: Any], let userID = dict[userIdKey] as? String {
              appState.setUserId(userID)
            }
            taskSource.set(result: true)
            appState.currentSessionDeviceInfo = deviceInfo
            appState.saveCurrentSessionDeviceInfo()
            self.setState(.success)
          } catch {
            let error = SDKError(ErrorType.parsingError)
            taskSource.set(error: error)
            self.setState(.failure(error))
          }
        } else {
          let error = SDKError(.unknown)
          taskSource.set(error: error)
          self.setState(.failure(error))
        }
      }
    } else {
      taskSource.set(result: true)
      setState(.success)
    }
    return taskSource.task
  }
}

extension Error {
  var coreErrorDescription: String {
    return (self as? SDKError)?.displayErrorMessage ?? localizedDescription
  }
}
