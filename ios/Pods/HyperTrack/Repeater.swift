import Foundation

final class Repeater: Equatable {
  /// State of the timer
  ///
  /// - paused: idle (never started yet or paused)
  /// - running: timer is running
  /// - executing: the observers are being executed
  /// - finished: timer lifetime is finished
  enum State: Equatable, CustomStringConvertible {
    case paused
    case running
    case executing
    case finished

    static func == (lhs: State, rhs: State) -> Bool {
      switch (lhs, rhs) {
        case (.paused, .paused), (.running, .running), (.executing, .executing),
             (.finished, .finished):
          return true
        default: return false
      }
    }

    /// Return `true` if timer is currently running, including when the observers are being executed.
    var isRunning: Bool {
      guard self == .running || self == .executing else { return false }
      return true
    }

    /// Return `true` if the observers are being executed.
    var isExecuting: Bool {
      guard case .executing = self else { return false }
      return true
    }

    /// Is timer finished its lifetime?
    /// It return always `false` for infinite timers.
    /// It return `true` for `.once` mode timer after the first fire,
    /// and when `.remainingIterations` is zero for `.finite` mode timers
    var isFinished: Bool {
      guard case .finished = self else { return false }
      return true
    }

    /// State description
    var description: String {
      switch self {
        case .paused: return "idle/paused"
        case .finished: return "finished"
        case .running: return "running"
        case .executing: return "executing"
      }
    }
  }

  /// Repeat interval
  enum Interval {
    case nanoseconds(_: Int)
    case microseconds(_: Int)
    case milliseconds(_: Int)
    case minutes(_: Int)
    case seconds(_: Double)
    case hours(_: Int)
    case days(_: Int)

    var value: DispatchTimeInterval {
      switch self {
        case let .nanoseconds(value): return .nanoseconds(value)
        case let .microseconds(value): return .microseconds(value)
        case let .milliseconds(value): return .milliseconds(value)
        case let .seconds(value):
          return .milliseconds(Int(Double(value) * Double(1000)))
        case let .minutes(value): return .seconds(value * 60)
        case let .hours(value): return .seconds(value * 3600)
        case let .days(value): return .seconds(value * 86400)
      }
    }
  }

  /// Mode of the timer.
  ///
  /// - infinite: infinite number of repeats.
  /// - finite: finite number of repeats.
  /// - once: single repeat.
  enum Mode {
    case infinite
    case finite(_: Int)
    case once

    /// Is timer a repeating timer?
    var isRepeating: Bool {
      switch self {
        case .once: return false
        default: return true
      }
    }

    /// Number of repeats, if applicable. Otherwise `nil`
    var countIterations: Int? {
      switch self {
        case let .finite(counts): return counts
        default: return nil
      }
    }

    /// Is infinite timer
    var isInfinite: Bool {
      guard case .infinite = self else { return false }
      return true
    }
  }

  /// Handler typealias
  typealias Observer = ((Repeater) -> Void)

  /// Token assigned to the observer
  typealias ObserverToken = UInt64

  /// Current state of the timer
  private(set) var state: State = .paused {
    didSet { onStateChanged?(self, state) }
  }

  /// Callback called to intercept state's change of the timer
  var onStateChanged: ((_ timer: Repeater, _ state: State) -> Void)?

  /// List of the observer of the timer
  private var observers = [ObserverToken: Observer]()

  /// Next token of the timer
  private var nextObserverID: UInt64 = 0

  /// Internal GCD Timer
  private var timer: DispatchSourceTimer?

  /// Is timer a repeat timer
  private(set) var mode: Mode

  /// Number of remaining repeats count
  private(set) var remainingIterations: Int?

  /// Interval of the timer
  private var interval: Interval

  /// Accuracy of the timer
  private var tolerance: DispatchTimeInterval

  /// Dispatch queue parent of the timer
  private var queue: DispatchQueue?

  /// Initialize a new timer.
  ///
  /// - Parameters:
  ///   - interval: interval of the timer
  ///   - mode: mode of the timer
  ///   - tolerance: tolerance of the timer, 0 is default.
  ///   - queue: queue in which the timer should be executed; if `nil` a new queue is created automatically.
  ///   - observer: observer
  init(
    interval: Interval,
    mode: Mode = .infinite,
    queue: DispatchQueue? = nil,
    tolerance: DispatchTimeInterval = .nanoseconds(0),
    observer: @escaping Observer
  ) {
    self.mode = mode
    self.interval = interval
    self.tolerance = tolerance
    remainingIterations = mode.countIterations
    self.queue = (queue ?? DispatchQueue(label: "com.repeat.queue"))
    timer = configureTimer()
    observe(observer)
  }

  /// Add new a listener to the timer.
  ///
  /// - Parameter callback: callback to call for fire events.
  /// - Returns: token used to remove the handler
  @discardableResult func observe(_ observer: @escaping Observer)
    -> ObserverToken {
    var (new, overflow) = nextObserverID.addingReportingOverflow(1)
    if overflow {
      // you need to add an incredible number of offset...sure you can't
      nextObserverID = 0
      new = 0
    }
    nextObserverID = new
    observers[new] = observer
    return new
  }

  /// Remove an observer of the timer.
  ///
  /// - Parameter id: id of the observer to remove
  func remove(observer identifier: ObserverToken) {
    observers.removeValue(forKey: identifier)
  }

  /// Remove all observers of the timer.
  ///
  /// - Parameter stopTimer: `true` to also stop timer by calling `pause()` function.
  func removeAllObservers(thenStop stopTimer: Bool = false) {
    observers.removeAll()

    if stopTimer { pause() }
  }

  /// Configure a new timer session.
  ///
  /// - Returns: dispatch timer
  private func configureTimer() -> DispatchSourceTimer {
    let associatedQueue = (
      queue ?? DispatchQueue(label: "com.repeat.\(NSUUID().uuidString)")
    )
    let timer = DispatchSource.makeTimerSource(queue: associatedQueue)
    let repeatInterval = interval.value
    let deadline: DispatchTime = (DispatchTime.now() + repeatInterval)
    if mode.isRepeating {
      timer.schedule(
        deadline: deadline,
        repeating: repeatInterval,
        leeway: tolerance
      )
    } else { timer.schedule(deadline: deadline, leeway: tolerance) }

    timer.setEventHandler { [weak self] in
      if let unwrapped = self { unwrapped.timeFired() }
    }
    return timer
  }

  /// Destroy current timer
  private func destroyTimer() {
    timer?.setEventHandler(handler: nil)
    timer?.cancel()

    if state == .paused || state == .finished { timer?.resume() }
  }

  /// Create and schedule a timer that will call `handler` once after the specified time.
  ///
  /// - Parameters:
  ///   - interval: interval delay for single fire
  ///   - queue: destination queue, if `nil` a new `DispatchQueue` is created automatically.
  ///   - observer: handler to call when timer fires.
  /// - Returns: timer instance
  @discardableResult class func once(
    after interval: Interval,
    queue: DispatchQueue? = nil,
    _ observer: @escaping Observer
  ) -> Repeater {
    let timer = Repeater(
      interval: interval,
      mode: .once,
      queue: queue,
      observer: observer
    )
    timer.start()
    return timer
  }

  /// Create and schedule a timer that will fire every interval optionally by limiting the number of fires.
  ///
  /// - Parameters:
  ///   - interval: interval of fire
  ///   - count: a non `nil` and > 0  value to limit the number of fire, `nil` to set it as infinite.
  ///   - queue: destination queue, if `nil` a new `DispatchQueue` is created automatically.
  ///   - handler: handler to call on fire
  /// - Returns: timer
  @discardableResult class func every(
    _ interval: Interval,
    count: Int? = nil,
    queue: DispatchQueue? = nil,
    _ handler: @escaping Observer
  ) -> Repeater {
    let mode: Mode = (count != nil ? .finite(count!) : .infinite)
    let timer = Repeater(
      interval: interval,
      mode: mode,
      queue: queue,
      observer: handler
    )
    timer.start()
    return timer
  }

  /// Force fire.
  ///
  /// - Parameter pause: `true` to pause after fire, `false` to continue the regular firing schedule.
  func fire(andPause pause: Bool = false) {
    timeFired()
    if pause == true { self.pause() }
  }

  /// Reset the state of the timer, optionally changing the fire interval.
  ///
  /// - Parameters:
  ///   - interval: new fire interval; pass `nil` to keep the latest interval set.
  ///   - restart: `true` to automatically restart the timer, `false` to keep it stopped after configuration.
  func reset(_ interval: Interval?, restart: Bool = true) {
    if state.isRunning { setPause(from: state) }

    // For finite counter we want to also reset the repeat count
    if case let .finite(count) = mode { self.remainingIterations = count }

    // Create a new instance of timer configured
    if let newInterval = interval { self.interval = newInterval }
    // update interval
    destroyTimer()
    timer = configureTimer()
    state = .paused

    if restart {
      timer?.resume()
      state = .running
    }
  }

  /// Start timer. If timer is already running it does nothing.
  @discardableResult func start() -> Bool {
    guard state.isRunning == false else { return false }

    // If timer has not finished its lifetime we want simply
    // restart it from the current state.
    guard state.isFinished == true else {
      state = .running
      timer?.resume()
      return true
    }

    // Otherwise we need to reset the state based upon the mode
    // and start it again.
    reset(nil, restart: true)
    return true
  }

  /// Pause a running timer. If timer is paused it does nothing.
  @discardableResult func pause() -> Bool {
    guard state != .paused, state != .finished else { return false }

    return setPause(from: state)
  }

  /// Pause a running timer optionally changing the state with regard to the current state.
  ///
  /// - Parameters:
  ///   - from: the state which the timer should only be paused if it is the current state
  ///   - to: the new state to change to if the timer is paused
  /// - Returns: `true` if timer is paused
  @discardableResult private func setPause(
    from currentState: State,
    to newState: State = .paused
  ) -> Bool {
    guard state == currentState else { return false }

    timer?.suspend()
    state = newState

    return true
  }

  /// Called when timer is fired
  private func timeFired() {
    state = .executing

    // dispatch to observers
    observers.values.forEach { $0(self) }

    // manage lifetime
    switch mode {
      case .once:
        // once timer's lifetime is finished after the first fire
        // you can reset it by calling `reset()` function.
        setPause(from: .executing, to: .finished)
      case .finite:
        // for finite intervals we decrement the left iterations count...
        remainingIterations! -= 1
        if remainingIterations! == 0 {
          // ...if left count is zero we just pause the timer and stop
          setPause(from: .executing, to: .finished)
        }
      case .infinite:
        // infinite timer does nothing special on the state machine
        break
    }
  }

  deinit {
    self.observers.removeAll()
    self.destroyTimer()
  }

  static func == (lhs: Repeater, rhs: Repeater) -> Bool { return lhs === rhs }
}
