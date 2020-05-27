import Foundation

private let lastLocationKey = "HTSDKCheckerLastLocationEventKey"

final class StandbyChecker {
  private weak var apiClient: AbstractAPIClient?
  private weak var appState: AbstractAppState?
  private weak var config: AbstractStandbyCheckerConfig?
  private weak var eventBus: AbstractEventBus?
  private weak var dataStore: AbstractReadWriteDataStore?
  private var repeatTimer: GCDRepeatingTimer?

  private let checkInterval: TimeInterval
  private var lastlocationData: LocationData?

  private var reachabilityStep: AbstractPipelineStep<Void, Bool>
  private var mapperStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Mapper, Pipeline.Transmission.Input.Network
    >
  private var networkStep:
    AbstractPipelineStep<
      Pipeline.Transmission.Input.Network,
      Pipeline.Transmission.Input.WriteDatabase
    >
  private let serialQueue = DispatchQueue(label: "com.hypertrack.sc.serial")

  init(
    _ configManager: AbstractConfigManager?,
    _ eventBus: AbstractEventBus?,
    _ appState: AbstractAppState?,
    _ apiClient: AbstractAPIClient?,
    _ reachability: AbstractReachabilityManager?,
    _ dataStore: AbstractReadWriteDataStore?
  ) {
    config = configManager?.config
    self.apiClient = apiClient
    self.appState = appState
    self.eventBus = eventBus
    self.dataStore = dataStore

    reachabilityStep = ReachabilityStep(reachability: reachability)
    mapperStep = TransmissionEventMapper()
    networkStep = TransmissionEventNetworkStep(
      input: Transmission.Input.Network(
        config: configManager?.config,
        apiClient: apiClient,
        deviceID: appState
      )
    )

    checkInterval = config?.standbyChecker.checkInterval
      ?? Constant.Config.StandbyChecker.checkInterval

    eventBus?.addObserver(
      self,
      selector: #selector(newEventFromLocationService(_:)),
      name: Constant.Notification.Location.NewEventAvalible.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(sendingEventComplete(_:)),
      name: Constant.Notification.Transmission.DataSentEvent.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(stopChecking),
      name: Constant.Notification.Tracking.Stopped.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(stopChecking),
      name: Constant.Notification.AuthToken.Inactive.name
    )
    eventBus?.addObserver(
      self,
      selector: #selector(startChecking),
      name: Constant.Notification.Tracking.Started.name
    )

    if let savedData = self.dataStore?.object(forKey: lastLocationKey) as? Data,
      let inferredLastlocationEvent = try? PropertyListDecoder().decode(
        LocationData.self,
        from: savedData
      )
    { lastlocationData = inferredLastlocationEvent }
  }

  @objc private func newEventFromLocationService(_ notification: Notification) {
    guard
      let location =
      notification.userInfo?[
        Constant.Notification.Location.NewEventAvalible.key
      ] as? LocationData
    else { return }
    lastlocationData = location
    dataStore?.set(
      try? PropertyListEncoder().encode(lastlocationData),
      forKey: lastLocationKey
    )
  }

  @objc private func sendingEventComplete(_: Notification) {
    resetTimer(timeInterval: checkInterval)
  }

  @objc func startChecking() {
    let toPing = config?.standbyChecker.toPing
      ?? Constant.Config.StandbyChecker.toPing
    if toPing == false { return }
    if repeatTimer == nil {
      logService.log("StandbyChacher start checking")
      repeatTimer = GCDRepeatingTimer(timeInterval: checkInterval)
    }
    fireTimer()
  }

  @objc func stopChecking() {
    logService.log("StandbyChacher stop checking")
    repeatTimer?.suspend()
  }

  private func fireTimer() {
    repeatTimer?.eventHandler = { [weak self] in
      self?.sendLastLocationEventToServer()
    }
  }

  private func resetTimer(timeInterval: TimeInterval) {
    repeatTimer?.reset(timeInterval: timeInterval)
  }

  deinit { self.eventBus?.removeObserver(self) }
}

extension StandbyChecker {
  private func sendLastLocationEventToServer() {
    guard let appState = self.appState,
      let lastlocationData = self.lastlocationData,
      let timestamp = lastlocationData.recorded_at
      else {
        resetTimer(timeInterval: checkInterval)
        return
    }
    let lastlocationDataEvent = LocationServiceData(
      id: UUID().uuidString,
      data: lastlocationData,
      recordedAt: timestamp
    )
    let event = Event(
      type: lastlocationDataEvent.getType(),
      sortedKey: lastlocationDataEvent.getSortedKey(),
      data: lastlocationDataEvent.getJSONdata(),
      id: lastlocationDataEvent.id,
      recordedAt: DateFormatter.iso8601Full.string(
        from: lastlocationDataEvent.getRecordedAt()
      )
    )

    logService.log("Sending to server standby event: \(event)")
    setState(.executing)
    reachabilityStep.execute(input: ()).continueWithTask(
      Executor.queue(serialQueue),
      continuation: {
        [unowned self] (task) -> Task<Pipeline.Transmission.Input.Network> in
        switch task.mapTaskToResult() {
          case .success:
            return self.mapperStep.execute(
              input: Pipeline.Transmission.Input.Mapper(
                events: [event],
                deviceId: appState.getDeviceId(),
                sdkVersion: appState.sdkVersion
              )
            )
          case let .failure(error): throw error
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
          case let .failure(error): throw error
        }
      }
    ).continueWith(
      Executor.queue(serialQueue),
      continuation: { [unowned self] task in
        switch task.mapTaskToResult() {
          case .success:
            self.setState(.success)
            self.resetTimer(timeInterval: self.checkInterval)
            logService.log("Sending .success standby event")
          case let .failure(error):
            self.setState(.failure(error))
            self.repeatTimer?.suspend()
            logService.error(
              "Sending standby event with error: \(prettyPrintSDKError(error))"
            )
            throw error
        }
      }
    )
  }
}

extension StandbyChecker: PipelineLogging {
  var context: Int { return Constant.Context.standbyChecker }

  func setState(
    _ type: Pipeline.State,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) { log(type, file: file, function: function, line: line) }
}
