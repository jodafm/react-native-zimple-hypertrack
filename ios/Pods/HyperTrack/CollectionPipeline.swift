import Foundation
import os

final class CollectionPipeline: AbstractCollectionPipeline {
  fileprivate weak var config: AbstractCollectionConfig?
  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate weak var databaseManager: AbstractDatabaseManager?
  fileprivate weak var appState: AbstractAppState?
  fileprivate let serialQueue = DispatchQueue(label: "com.hypertrack.cp.serial")
  fileprivate var collectionType = EventCollectionType.online
  fileprivate let errorHandler: AbstractErrorHandler?
  fileprivate let stepOne: AbstractPipelineStep<[AbstractServiceData], [Event]>
  fileprivate let stepTwo:
    AbstractPipelineStep<Pipeline.Collection.Input.DatabaseWrite, Bool>

  var context: Int { return Constant.Context.collectionPipeline }

  var isExecuting: Bool = false

  struct Input {
    let config: AbstractCollectionConfig?
    let eventBus: AbstractEventBus?
    let databaseManager: AbstractDatabaseManager?
    let appState: AbstractAppState?
  }

  struct ExecuteInput {
    let events: [AbstractServiceData]
    let collectionType: EventCollectionType
  }

  init(_ input: Input, _ errorHandler: AbstractErrorHandler?) {
    config = input.config
    eventBus = input.eventBus
    databaseManager = input.databaseManager
    appState = input.appState
    self.errorHandler = errorHandler
    stepOne = CollectionMappingEntity()
    stepTwo = CollectionWriteDataBaseEntity(config: input.config)
  }

  func sendEvents<T>(
    events: [T],
    eventCollectedIn collectionType: EventCollectionType
  ) where T: AbstractServiceData {
    execute(
      input: CollectionPipeline.ExecuteInput(
        events: events,
        collectionType: collectionType
      )
    )
  }

  func sendEvents<T>(events: [T]) where T: AbstractServiceData {
    execute(
      input: CollectionPipeline.ExecuteInput(
        events: events,
        collectionType: collectionType
      )
    )
  }
}

extension CollectionPipeline {
  func tripMarkerEvent(_ metaData: [String: Any]) {
    let tripMarkerEvent = TripMarker(withDict: metaData)
    execute(
      input: CollectionPipeline.ExecuteInput(
        events: [tripMarkerEvent],
        collectionType: EventCollectionType.custom
      )
    )
  }
}

extension CollectionPipeline: AbstractPipeline {
  func execute(completionHandler _: ((SDKError?) -> Void)?) {}

  func execute(input: ExecuteInput) {
    if let lastOnlineInfo = appState?.getLastOnlineSessionInfo(),
      !lastOnlineInfo.isReachable,
      lastOnlineInfo.date.addingTimeInterval(
        Constant.Config.Collection.timeToStopRecordingData
      ) < Date() {
      logCollection.log(
        "Aborting execution of CollectionPipeline because offline buffer of \(Constant.Config.Collection.timeToStopRecordingData / 60 / 60) hours started at \(lastOnlineInfo.date) is reached with isReachable: \(lastOnlineInfo.isReachable)"
      )
      errorHandler?.handleError(SDKError(.networkDisconnectedGreater12Hours))
      return
    } else { errorHandler?.resetNetworkErrorFlag() }
    _ = input.events.map {
      logCollection.log(
        "Executing event: \(prettyPrintAbstractServiceData($0))"
      )
    }
    setState(.executing)
    let database = databaseManager?.getDatabaseManager(input.collectionType)
    stepOne.execute(input: input.events).continueWithTask(
      Executor.queue(serialQueue),
      continuation: { [unowned self] (task) -> Task<Bool> in
        switch task.mapTaskToResult() {
          case let .success(result):
            return self.stepTwo.execute(
              input: Pipeline.Collection.Input.DatabaseWrite(
                events: result,
                database: database
              )
            )
          case let .failure(error): throw error
        }
      }
    ).continueOnSuccessWith { [weak self] _ in
      guard let self = self else { return }
      self.setState(.success)
      self.eventBus?.post(
        name: Constant.Notification.Database.DataAvailableEvent.name,
        userInfo: [
          Constant.Notification.Database.DataAvailableEvent.key: input
            .collectionType
        ]
      )
    }
  }
}
