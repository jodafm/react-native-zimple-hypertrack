import Foundation
import UIKit

private let backgroundTaskName = "HTDispatchTask"

protocol AbstractDispatch: AnyObject { func dispatch() }

final class Dispatch {
  private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier =
    UIBackgroundTaskIdentifier.invalid
  private weak var eventBus: AbstractEventBus?
  private weak var config: AbstractDispatchConfig?
  private weak var transmission: AbstractPipeline?
  private var strategy: AbstractDispatchStrategy?
  private var context: AbstractDispatchStrategyContext?
  fileprivate var type: Config.Dispatch.DispatchType

  init(
    _ eventBus: AbstractEventBus?,
    _ config: AbstractDispatchConfig?,
    _ context: AbstractDispatchStrategyContext?,
    _ transmission: AbstractPipeline?
  ) {
    self.eventBus = eventBus
    self.config = config
    self.context = context
    self.transmission = transmission
    type = config?.dispatch.type ?? .manual
    strategy = context?.getDispatchStrategy(self, config: config)
    self.eventBus?.addObserver(
      self,
      selector: #selector(onAppBackground(_:)),
      name: UIApplication.didEnterBackgroundNotification.rawValue
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(reachabilityChanged(_:)),
      name: Constant.Notification.Network.ReachabilityEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(dispatchTypeChanged(_:)),
      name: Constant.Notification.Dispatch.TypeChangedEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(dataAvailable(_:)),
      name: Constant.Notification.Database.DataAvailableEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(transmissionDone(_:)),
      name: Constant.Notification.Transmission.DataSentEvent.name
    )
    self.eventBus?.addObserver(
      self,
      selector: #selector(authTokenInactive(_:)),
      name: Constant.Notification.AuthToken.Inactive.name
    )
  }

  @objc private func dispatchTypeChanged(_ notification: Notification) {
    guard
      let value =
      notification.userInfo?[
        Constant.Notification.Dispatch.TypeChangedEvent.key
      ] as? Int,
      let type = Config.Dispatch.DispatchType(rawValue: value)
      else { return }
    if type != self.type {
      strategy = context?.getDispatchStrategy(self, config: config)
      self.type = type
    }
  }

  @objc private func onAppBackground(_ notification: Notification) {
    strategy?.stop()
    logGeneral.debug(
      "Created background task with notification: \(notification)"
    )
    backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
      withName: backgroundTaskName
    ) { self.endBackgroundTask() }
    strategy?.start()
  }

  private func endBackgroundTask() {
    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
    backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
  }

  @objc private func dataAvailable(_: Notification) {
    strategy?.start()
  }

  @objc private func transmissionDone(_: Notification) {
    strategy?.stop()
  }

  @objc private func authTokenInactive(_: Notification) {
    strategy?.stop()
  }

  @objc private func reachabilityChanged(_ notification: Notification) {
    guard
      let value =
      notification.userInfo?[
        Constant.Notification.Network.ReachabilityEvent.key
      ] as? Bool, !value
    else { return }
    strategy?.stop()
  }
}

extension Dispatch: AbstractDispatch {
  func dispatch() { transmission?.execute(completionHandler: nil) }
}

protocol AbstractDispatchStrategy {
  var dispatch: AbstractDispatch? { get }
  func start()
  func stop()
  func updateConfig(_ config: AbstractDispatchConfig?)
}

protocol AbstractDispatchStrategyContext {
  func getDispatchStrategy(
    _ dispatch: AbstractDispatch,
    config: AbstractDispatchConfig?
  ) -> AbstractDispatchStrategy?
}

final class DispatchStrategyContext: AbstractDispatchStrategyContext {
  func getDispatchStrategy(
    _ dispatch: AbstractDispatch,
    config: AbstractDispatchConfig?
  ) -> AbstractDispatchStrategy? {
    guard let config = config else { return nil }
    switch config.dispatch.type {
      case .timer:
        return TimerDispatchStrategy(dispatch: dispatch, config: config)
      default: return nil
    }
  }
}

final class TimerDispatchStrategy: AbstractDispatchStrategy {
  weak var dispatch: AbstractDispatch?
  var timer: Repeater?
  var debouncer: Debouncer?

  var frequency: Double {
    return config?.dispatch.frequency ?? Constant.Config.Dispatch.frequency
  }

  var debounce: Double {
    return config?.dispatch.debounce ?? Constant.Config.Dispatch.debounce
  }

  var tolerance: Int {
    return config?.dispatch.tolerance ?? Constant.Config.Dispatch.tolerance
  }

  fileprivate weak var config: AbstractDispatchConfig?

  init(dispatch: AbstractDispatch?, config: AbstractDispatchConfig?) {
    self.dispatch = dispatch
    self.config = config
    timer = Repeater(
      interval: Repeater.Interval.seconds(frequency),
      mode: .infinite,
      queue: DispatchQueue.global(qos: .background),
      tolerance: .seconds(tolerance)
    ) { [weak self] _ in self?.dispatch?.dispatch() }
    debouncer = Debouncer(
      Repeater.Interval.seconds(debounce),
      callback: { [weak self] in self?.timer?.start() }
    )
  }

  func start() { debouncer?.call() }

  func stop() { timer?.pause() }

  func updateConfig(_ config: AbstractDispatchConfig?) {
    guard frequency != config?.dispatch.frequency else { return }
    self.config = config
    timer?.reset(Repeater.Interval.seconds(frequency), restart: false)
  }

  deinit { timer?.removeAllObservers(thenStop: true) }
}
