import Foundation

/// The Debouncer will delay a function call, and every time it's getting called it will
/// delay the preceding call until the delay time is over.
final class Debouncer {
  /// Typealias for callback type
  typealias Callback = (() -> Void)

  /// Delay interval
  let delay: Repeater.Interval

  /// Callback to activate
  var callback: Callback?

  /// Internal timer to fire callback event.
  private var timer: Repeater?

  /// Initialize a new debouncer with given delay and callback.
  /// Debouncer class to delay functions that only get delay each other until the timer fires.
  ///
  /// - Parameters:
  ///   - delay: delay interval
  ///   - callback: callback to activate
  init(_ delay: Repeater.Interval, callback: Callback? = nil) {
    self.delay = delay
    self.callback = callback
  }

  /// Call debouncer to start the callback after the delayed time.
  /// Multiple calls will ignore the older calls and overwrite the firing time.
  func call() {
    if timer == nil {
      timer = Repeater.once(
        after: delay,
        { _ in
          guard let callback = self.callback else {
            debugPrint("Debouncer fired but callback not set.")
            return
          }
          callback()
        }
      )
    } else { timer?.reset(delay, restart: true) }
  }
}
