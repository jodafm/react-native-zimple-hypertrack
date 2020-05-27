import UIKit

protocol AbstractSettings: AnyObject { func getSettings() }

final class DeviceSettings: AbstractSettings {
  fileprivate weak var appState: AbstractAppState?
  fileprivate weak var apiClient: AbstractAPIClient?
  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate weak var serviceManager: AbstractServiceManager?
  fileprivate weak var initializationPipeline: InitializationPipeline?

  fileprivate var lastReceivedDeviceSettingsDate: Date?
  fileprivate var delayInterval: TimeInterval = Constant.Config.DeviceSettings
    .delayInterval

  init(
    _ appState: AbstractAppState?,
    _ apiClient: AbstractAPIClient?,
    _ eventBus: AbstractEventBus?,
    _ serviceManager: AbstractServiceManager?,
    _ initializationPipeline: InitializationPipeline?
  ) {
    self.appState = appState
    self.apiClient = apiClient
    self.eventBus = eventBus
    self.serviceManager = serviceManager
    self.initializationPipeline = initializationPipeline
  }

  func getSettings() {
    if lastReceivedDeviceSettingsDate == nil {
      lastReceivedDeviceSettingsDate = Date()
      settingsServerRequest()
    } else if let date = lastReceivedDeviceSettingsDate,
      date.addingTimeInterval(delayInterval) <= Date() {
      lastReceivedDeviceSettingsDate = Date()
      settingsServerRequest()
    } else {
      logNetwork.info(
        "Attempt to reuse the \(#function) before the delay time is over. Last call was: \(String(describing: lastReceivedDeviceSettingsDate))"
      )
    }
  }

  private func settingsServerRequest() {
    guard let apiClient = self.apiClient else { return }
    logNetwork.info("Executing device settings.")

    setState(.executing)
    apiClient.makeRequest(ApiRouter.deviceSettings).continueWith(continuation: {
      [weak self] (task) -> Void in guard let self = self else { return }
      if let response = task.result {
        self.receivedDeviceSettings(response)
        self.setState(.success)
      } else if let error = task.error {
        logNetwork.error(
          "Failed to execute the request: \(ApiRouter.deviceSettings) with error: \(error.localizedDescription)"
        )
        self.setState(.failure(error))
      }
    })
  }

  private func receivedDeviceSettings(_ response: Response) {
    guard let data = response.data else { return }
    guard let initPipeline = self.initializationPipeline else { return }
    guard let serviceManager = self.serviceManager else { return }
    if let payload = try? JSONSerialization.jsonObject(
      with: data,
      options: JSONSerialization.ReadingOptions.allowFragments
    ) as? [String: Any], let data = payload {
      logNetwork.info("Received device settings: \(data)")
      if let isStartTracking = data[Constant.ServerKeys.DeviceSettings.tracking]
        as? String,
        let state = Constant.ServerKeys.TrackingState(
          rawValue: isStartTracking
        ) {
        switch state {
          case .stopTracking: initPipeline.stopTracking(for: .settingsStop)
          case .startTracking:
            if serviceManager.numberOfRunningServices()
              != serviceManager.numberOfServices()
            { initPipeline.startTracking(for: .settingsStart) } else {
              logNetwork.info("Attempt to \(#function), when tracking is started")
            }
        }
      }
    }
  }
}

extension DeviceSettings: PipelineLogging {
  var context: Int { return Constant.Context.deviceSettings }

  func setState(
    _ type: Pipeline.State,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) { log(type, file: file, function: function, line: line) }
}
