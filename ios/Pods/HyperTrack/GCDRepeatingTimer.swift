import Foundation

final class GCDRepeatingTimer {
  var timeInterval: TimeInterval

  init(timeInterval: TimeInterval) { self.timeInterval = timeInterval }

  private lazy var timer: DispatchSourceTimer = {
    let timerSource = DispatchSource.makeTimerSource()
    timerSource.schedule(deadline: .now(), repeating: self.timeInterval)
    timerSource.setEventHandler(handler: { [weak self] in self?.eventHandler?()
    })
    return timerSource
  }()

  var eventHandler: (() -> Void)?

  private enum State {
    case suspended
    case resumed
  }

  private var state: State = .suspended

  deinit {
    timer.setEventHandler {}
    timer.cancel()
    // If the timer is suspended, calling cancel without resuming
    //         triggers a crash. This is documented here
    //         https://forums.developer.apple.com/thread/15902
    resume()
    eventHandler = nil
  }

  func resume() {
    if state == .resumed { return }
    state = .resumed
    timer.resume()
  }

  func suspend() {
    if state == .suspended { return }
    state = .suspended
    timer.suspend()
  }

  func reset(timeInterval: TimeInterval) {
    self.timeInterval = timeInterval
    timer.schedule(
      deadline: .now() + self.timeInterval,
      repeating: self.timeInterval
    )
    resume()
  }
}
