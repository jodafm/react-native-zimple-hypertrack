import Foundation

protocol AbstractTransmissionPipeline: AbstractPipeline {
  var config: AbstractTransmissionConfig? { get }
  var deviceId: GetDeviceIdProtocol? { get }
  var sdkVersion: GetSDKVersionProtocol? { get }
  var eventBus: AbstractEventBus? { get }
  var database: EventsTableManager? { get }
  var serialQueue: DispatchQueue { get }
  var reachabilityStep: AbstractPipelineStep<Void, Bool> { get }
  var stepRegistration: AbstractPipelineStep<Void, Bool> { get }
  var databaseReadStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.ReadDatabase,
      Pipeline.Transmission.Input.Mapper
    >
  { get }
  var mapperStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Mapper, Pipeline.Transmission.Input.Network
    >
  { get }
  var networkStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Network,
      Pipeline.Transmission.Input.WriteDatabase
    >
  { get }
  var databaseWriteStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.WriteDatabase,
      Pipeline.Transmission.Input.PipelineEnded
    >
  { get }
}

extension AbstractTransmissionPipeline {
  func execute(completionHandler: ((SDKError?) -> Void)?) {
    setState(.executing)
    reachabilityStep.execute(input: ()).continueWithTask(
      Executor.queue(serialQueue),
      continuation: { [unowned self] (task) -> Task<Bool> in
        switch task.mapTaskToResult() {
          case .success: return self.stepRegistration.execute(input: ())
          case let .failure(error):
            completionHandler?(error)
            throw error
        }
      }
    ).continueWithTask(
      Executor.queue(serialQueue),
      continuation: {
        [unowned self] (task) -> Task<Pipeline.Transmission.Input.Mapper> in
        switch task.mapTaskToResult() {
          case .success:
            return self.databaseReadStep.execute(
              input: Pipeline.Transmission.Input.ReadDatabase(
                deviceId: self.deviceId?.getDeviceId() ?? "",
                sdkVersion: self.sdkVersion?.sdkVersion ?? ""
              )
            )
          case let .failure(error):
            completionHandler?(error)
            throw error
        }
      }
    ).continueWithTask(
      Executor.queue(serialQueue),
      continuation: {
        [unowned self] (task) -> Task<Pipeline.Transmission.Input.Network> in
        switch task.mapTaskToResult() {
          case let .success(result): return self.mapperStep.execute(
          input: result
          )
          case let .failure(error):
            completionHandler?(error)
            throw error
        }
      }
    ).continueWithTask(
      Executor.queue(serialQueue),
      continuation: {
        [unowned self] (task) -> Task<Pipeline.Transmission.Input.WriteDatabase>
          in
        switch task.mapTaskToResult() {
          case let .success(result):
            return self.networkStep.execute(input: result)
          case let .failure(error):
            completionHandler?(error)
            throw error
        }
      }
    ).continueWithTask(
      Executor.queue(serialQueue),
      continuation: {
        [unowned self] (task) -> Task<Pipeline.Transmission.Input.PipelineEnded>
          in
        switch task.mapTaskToResult() {
          case let .success(result):
            return self.databaseWriteStep.execute(input: result)
          case let .failure(error):
            completionHandler?(error)
            throw error
        }
      }
    ).continueWith(
      Executor.queue(serialQueue),
      continuation: { [unowned self] task in
        switch task.mapTaskToResult() {
          case let .success(result):
            self.setState(.success)
            if let batchSize = self.config?.transmission.batchSize,
              UInt(result.events.count) < batchSize {
              self.eventBus?.post(
                name: Constant.Notification.Transmission.DataSentEvent.name,
                userInfo: nil
              )
              completionHandler?(nil)
            } else { self.execute(completionHandler: completionHandler) }
          case let .failure(error):
            self.setState(.failure(error))
            completionHandler?(error)
            throw error
        }
      }
    )
  }
}

final class TransmissionPipeline {
  weak var config: AbstractTransmissionConfig?
  weak var eventBus: AbstractEventBus?
  weak var database: EventsTableManager?
  weak var deviceId: GetDeviceIdProtocol?
  weak var sdkVersion: GetSDKVersionProtocol?
  let serialQueue: DispatchQueue
  let batchSize: UInt

  var context: Int { return Constant.Context.transmissionPipeline }

  var isExecuting: Bool = false

  let reachabilityStep: AbstractPipelineStep<Void, Bool>
  let stepRegistration: AbstractPipelineStep<Void, Bool>
  let databaseReadStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.ReadDatabase,
      Pipeline.Transmission.Input.Mapper
    >
  let mapperStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Mapper, Pipeline.Transmission.Input.Network
    >
  let networkStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Network,
      Pipeline.Transmission.Input.WriteDatabase
    >
  let databaseWriteStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.WriteDatabase,
      Pipeline.Transmission.Input.PipelineEnded
    >

  init(input: Input) {
    config = input.config
    eventBus = input.eventBus
    database = input.database
    batchSize = input.batchSize
    deviceId = input.deviceId
    sdkVersion = input.sdkVersion
    serialQueue = DispatchQueue(label: input.queueName)
    reachabilityStep = ReachabilityStep(reachability: input.reachability)
    stepRegistration = InitDeviceRegistrationEntity(
      apiClient: input.apiClient,
      appState: input.appState
    )
    databaseReadStep = TransmissionReadDatabaseStep(
      input: Transmission.Input.Database(
        batchSize: input.batchSize,
        config: input.config,
        database: input.database
      )
    )
    mapperStep = input.mapperStep
    networkStep = input.networkStep
    databaseWriteStep = TransmissionWriteDatabaseStep(
      input: Transmission.Input.Database(
        batchSize: input.batchSize,
        config: input.config,
        database: input.database
      )
    )
    eventBus?.addObserver(
      self,
      selector: #selector(execute),
      name: Constant.Notification.Transmission.SendDataEvent.name
    )
  }

  @objc private func execute() { execute(completionHandler: nil) }

  struct Input {
    let apiClient: AbstractAPIClient?
    let appState: AbstractAppState?
    let queueName: String
    let batchSize: UInt
    let config: AbstractTransmissionConfig?
    let eventBus: AbstractEventBus?
    let database: EventsTableManager?
    let networkStep:
      AbstractPipelineStep<
        Pipeline.Transmission.Input.Network,
        Pipeline.Transmission.Input.WriteDatabase
      >
    let deviceId: GetDeviceIdProtocol?
    let sdkVersion: GetSDKVersionProtocol?
    let reachability: AbstractReachabilityManager?
    let mapperStep:
      AbstractPipelineStep<
        Pipeline.Transmission.Input.Mapper, Pipeline.Transmission.Input.Network
      >
  }
}

extension TransmissionPipeline: AbstractTransmissionPipeline {}
protocol AbstractTransmissionManager: AbstractPipeline {}

final class TransmissionManager {
  struct Input {
    let collectionTypes: [EventCollectionType]
    let config: AbstractTransmissionConfig
    let eventBus: AbstractEventBus?
    let databaseManager: AbstractDatabaseManager?
    let apiClient: AbstractAPIClient?
    let appState: AbstractAppState?
    let sdkVersion: GetSDKVersionProtocol?
    let reachability: AbstractReachabilityManager?
  }

  fileprivate var instances: [EventCollectionType: TransmissionPipeline] = [:]

  var context: Int { return Constant.Context.transmissionPipeline }

  var isExecuting: Bool = false

  init(_ input: Input) {
    let queueNamePrefix = "com.hypertrack.tp.serial"
    input.collectionTypes.forEach {
      instances[$0] = TransmissionPipeline(
        input: TransmissionPipeline.Input(
          apiClient: input.apiClient,
          appState: input.appState,
          queueName: "\(queueNamePrefix).\($0.tableName())",
          batchSize: input.config.transmission.batchSize,
          config: input.config,
          eventBus: input.eventBus,
          database: input.databaseManager?.getDatabaseManager($0),
          networkStep: $0 == .online
            ? TransmissionEventNetworkStep(
              input: Transmission.Input.Network(
                config: input.config,
                apiClient: input.apiClient,
                deviceID: input.appState
              )
            )
            : TransmissionCustomEventNetworkStep(
              input: Transmission.Input.Network(
                config: input.config,
                apiClient: input.apiClient,
                deviceID: input.appState
              )
            ),
          deviceId: input.appState,
          sdkVersion: input.sdkVersion,
          reachability: input.reachability,
          mapperStep: TransmissionEventMapper()
        )
      )
    }
  }
}

extension TransmissionManager: AbstractTransmissionManager {
  func execute(completionHandler: ((SDKError?) -> Void)?) {
    guard !isExecuting else { return }
    setState(.executing)
    instances[.online]?.execute(completionHandler: { [weak self] error in
      if let error = error {
        completionHandler?(error)
        self?.setState(.failure(error))
      } else {
        self?.instances[.custom]?.execute(completionHandler: { error in
          if let error = error { self?.setState(.failure(error)) } else {
            self?.setState(.success)
          }
          completionHandler?(error)
        })
      }
    })
  }
}
