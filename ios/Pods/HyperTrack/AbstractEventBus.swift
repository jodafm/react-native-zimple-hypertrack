import Foundation

protocol AbstractEventBus: AnyObject {
  func addObserver(
    _ observer: Any,
    selector aSelector: Selector,
    name aName: String
  )
  func post(name aName: String, userInfo aUserInfo: [AnyHashable: Any]?)
  func post(name aName: String, error: Error)
  func removeObserver(_ observer: Any)
  func removeObserver(_ observer: Any, name aName: String)
}

final class EventBusWrapper {
  lazy var center: AbstractEventBus = { NotificationCenterEventBus() }()
}

final class NotificationCenterEventBus {
  private let center: NotificationCenter

  init() { center = NotificationCenter.default }
}

extension NotificationCenterEventBus: AbstractEventBus {
  func addObserver(
    _ observer: Any,
    selector aSelector: Selector,
    name aName: String
  ) {
    let notificationName = NSNotification.Name(aName)
    DispatchQueue.main.async {
      self.center.removeObserver(observer, name: notificationName, object: nil)
      self.center.addObserver(
        observer,
        selector: aSelector,
        name: notificationName,
        object: nil
      )
    }
  }

  func post(name aName: String, userInfo aUserInfo: [AnyHashable: Any]?) {
    DispatchQueue.main.async {
      self.center.post(
        name: NSNotification.Name(aName),
        object: nil,
        userInfo: aUserInfo
      )
    }
  }

  func post(name aName: String, error: Error) {
    DispatchQueue.main.async {
      self.center.post(
        name: NSNotification.Name(aName),
        object: nil,
        userInfo: [Constant.Notification.Payload.errorKey: error]
      )
    }
  }

  func removeObserver(_ observer: Any) {
    DispatchQueue.main.async { self.center.removeObserver(observer) }
  }

  func removeObserver(_ observer: Any, name aName: String) {
    DispatchQueue.main.async {
      self.center.removeObserver(
        observer,
        name: NSNotification.Name(aName),
        object: nil
      )
    }
  }
}
