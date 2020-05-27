import CoreTelephony
import Foundation

private typealias ReachabilityEvent = Constant.Notification.Network
  .ReachabilityEvent

protocol AbstractReachabilityManager: AnyObject {
  var isReachable: Bool { get }
  var networkType: ReachabilityManager.NetworkType { get }
}

final class ReachabilityManager: AbstractReachabilityManager {
  fileprivate weak var config: AbstractNetworkConfig?
  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate let reachability: Reachability

  private(set) var isReachable: Bool = false {
    didSet {
      eventBus?.post(
        name: ReachabilityEvent.name,
        userInfo: [ReachabilityEvent.key: isReachable]
      )
    }
  }

  private(set) var networkType: NetworkType = .unavailable {
    didSet {
      switch networkType {
        case .unavailable: isReachable = false
        default: isReachable = true
      }
    }
  }

  enum NetworkType: String {
    case wifi = "WiFi"
    case wwan = "WWAN"
    case unavailable = "Unavailable"
  }

  init(_ config: AbstractNetworkConfig?, _ eventBus: AbstractEventBus?) {
    self.config = config
    self.eventBus = eventBus
    reachability = Reachability.forInternetConnection()

    self.eventBus?.addObserver(
      self,
      selector: #selector(reachabilityStatusChanged(_:)),
      name: NSNotification.Name.reachabilityChanged.rawValue
    )

    reachability.reachableOnWWAN = true
    reachability.startNotifier()
    isReachable = reachability.isReachable()
  }

  @objc fileprivate func reachabilityStatusChanged(_ sender: NSNotification) {
    guard
      let networkStatus = (sender.object as? Reachability)?
      .currentReachabilityStatus()
      else { return }
    updateInterfaceWithCurrent(networkStatus: networkStatus)
  }

  fileprivate func updateInterfaceWithCurrent(networkStatus: NetworkStatus) {
    switch networkStatus {
      case .NotReachable: networkType = .unavailable
      case .ReachableViaWiFi: networkType = .wifi
      case .ReachableViaWWAN: networkType = .wwan
      @unknown default: return
    }
  }

  deinit { reachability.stopNotifier() }
}
