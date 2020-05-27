import Foundation

protocol AuthTokenProvider: AnyObject {
  var authToken: AuthToken? { get set }
  var status: AuthManager.Status { get set }
  func makeHTAccountInactive(with error: SDKError)
  func removeAuthToken()
}

final class AuthManager: AuthTokenProvider {
  fileprivate let statusKey = "com.hypertrack.sdk.core.auth.status"
  fileprivate let authTokenKey = "com.hypertrack.sdk.core.auth.token"
  fileprivate let authExpiresInKey = "com.hypertrack.sdk.core.auth.expiresIn"

  fileprivate weak var eventBus: AbstractEventBus?
  fileprivate weak var appState: AbstractAppState?
  fileprivate weak var config: AbstractNetworkConfig?
  fileprivate weak var dataBase: AbstractDatabaseManager?
  fileprivate weak var serviceManager: BaseServiceManager?
  fileprivate weak var errorHandler: AbstractErrorHandler?
  fileprivate weak var dataStore: AbstractReadWriteDataStore?

  var status: AuthManager.Status = .active {
    didSet { if status == .active { validTokenReceived() } }
  }

  var authToken: AuthToken? {
    didSet {
      guard let authToken = authToken else {
        dataStore?.removeObject(forKey: authTokenKey)
        return
      }
      guard oldValue?.token != authToken.token else { return }
      dataStore?.set(
        try? JSONEncoder.hyperTrackEncoder.encode(authToken),
        forKey: authTokenKey
      )
    }
  }

  init(
    _ config: AbstractNetworkConfig?,
    _ dataStore: AbstractReadWriteDataStore?,
    _ serviceManager: BaseServiceManager?,
    _ eventBus: AbstractEventBus?,
    _ databaseManager: AbstractDatabaseManager?,
    _ appState: AbstractAppState?,
    _ errorHandler: AbstractErrorHandler?
  ) {
    self.config = config
    self.dataStore = dataStore
    self.serviceManager = serviceManager
    self.eventBus = eventBus
    dataBase = databaseManager
    self.errorHandler = errorHandler
    self.appState = appState
    if let data = dataStore?.data(forKey: authTokenKey) {
      authToken = try? JSONDecoder.hyperTrackDecoder.decode(
        AuthToken.self,
        from: data
      )
    }
    if let data = dataStore?.data(forKey: statusKey) {
      do {
        status = try JSONDecoder.hyperTrackDecoder.decode(
          Status.self,
          from: data
        )
      } catch { status = .active }
    }
  }

  func makeHTAccountInactive(with error: SDKError) {
    logGeneral.error(
      "Making HyperTrack account inactive with error: \(prettyPrintSDKError(error))"
    )
    status = .inactive
    serviceManager?.stopAllServices()

    dataBase?.getDatabaseManager(.online)?.deleteAll(result: {
      transactionState in
      if transactionState {
        logGeneral.info("Removed all items from online database table")
      } else {
        logGeneral.error(
          "Error occured when removed all items from online database table"
        )
      }
    })
    dataBase?.getDatabaseManager(.custom)?.deleteAll(result: {
      transactionState in
      if transactionState {
        logGeneral.info("Removed all items from custom database table")
      } else {
        logGeneral.error(
          "Error occured when removed all items from custom database table"
        )
      }
    })
    authToken? = AuthToken()
    eventBus?.post(
      name: Constant.Notification.AuthToken.Inactive.name,
      userInfo: nil
    )
    eventBus?.post(
      name: Constant.Notification.Tracking.Stopped.name,
      userInfo: [
        Constant.Notification.Tracking.TrackingReason.key: TrackingReason
          .trialEnded
      ]
    )
    appState?.userTrackingBehaviour = .paused
    errorHandler?.handleError(error)
  }

  func removeAuthToken() {
    eventBus?.post(
      name: Constant.Notification.AuthToken.Inactive.name,
      userInfo: nil
    )
    authToken? = AuthToken()
    status = .inactive
    dataStore?.removeObject(forKey: authTokenKey)
    dataStore?.removeObject(forKey: statusKey)
  }

  func validTokenReceived() { errorHandler?.resetTrialEndedErrorFlag() }

  enum Status: Int, Codable {
    case active = 0
    case inactive
  }
}
