import Foundation

/// The HyperTrack Error object. Contains an error type.
final class SDKError: NSObject, Error {
  /**
   Enum for various error types
   */
  let type: ErrorType

  @objc var errorCode: Int { return type.rawValue }

  @objc let errorMessage: String

  var displayErrorMessage: String { return type.toString() }

  init(code: Int) {
    type = ErrorType(rawValue: code)
    errorMessage = type.toString()
  }

  init(_ type: ErrorType) {
    self.type = type
    errorMessage = type.toString()
  }

  init(_ type: ErrorType, responseData: Data?) {
    self.type = type
    if let data = responseData,
      let errorMessage = String(data: data, encoding: .utf8)
    { self.errorMessage = errorMessage } else { errorMessage = "" }
  }

  init(_ type: ErrorType, message: String?) {
    self.type = type
    if let errorMessage = message { self.errorMessage = errorMessage } else {
      errorMessage = ""
    }
  }

  static var `default`: SDKError { return SDKError(.unknown) }

  func toDict() -> [String: Any] {
    return ["code": self.errorCode, "message": self.errorMessage]
  }

  func toJson() -> String {
    let dict = toDict()
    do {
      let jsonData = try JSONSerialization.data(withJSONObject: dict)
      let jsonString = String(data: jsonData, encoding: String.Encoding.utf8)
      return jsonString ?? ""
    } catch { return "" }
  }

  var isServerError: Bool {
    switch type {
      case .internalServerError: return true
      default: return false
    }
  }

  var isAuthorizationFailed: Bool {
    switch type {
      case .authorizationFailed:
        return true
      default:
        return false
    }
  }

  var isTrialPeriodExpired: Bool {
    if type == .forbidden, errorMessage == "trial ended" {
      return true
    } else { return false }
  }
}

enum ErrorType {
  case badRequest
  case authorizationFailed
  case forbidden
  case internalServerError
  case urlErrorUnknown
  case urlErrorCancelled
  case urlErrorBadURL
  case urlErrorTimedOut
  case urlErrorUnsupportedURL
  case urlErrorCannotFindHost
  case urlErrorCannotConnectToHost
  case urlErrorNetworkConnectionLost
  case urlErrorNotConnectedToInternet
  case parsingError
  case locationPermissionsDenied
  case locationServicesDisabled
  case activityPermissionsDenied
  case activityServicesDisabled
  case serviceAlreadyRunning
  case serviceAlreadyStopped
  case networkDisconnected
  case networkDisconnectedGreater12Hours
  case databaseReadFailed
  case databaseWriteFailed
  case sensorToDataMappingFailed
  case deviceIdBlank
  case emptyResult
  case unknownService
  case publishableKeyisNotSet(String)
  case invalidToken
  case emptyData
  case invalidMetadata
  case unknown

  func toString() -> String {
    switch self {
      case .urlErrorUnknown: return "Unable to connect to the internet"
      case .urlErrorCancelled:
        return
          "The connection failed because the user cancelled required authentication"
      case .urlErrorBadURL: return "Bad URL"
      case .urlErrorTimedOut: return "The connection timed out"
      case .urlErrorUnsupportedURL: return "URL not supported"
      case .urlErrorCannotFindHost:
        return "The connection failed because the host could not be found"
      case .urlErrorCannotConnectToHost:
        return
          "The connection failed because a connection cannot be made to the host"
      case .urlErrorNetworkConnectionLost:
        return "The connection failed because the network connection was lost"
      case .urlErrorNotConnectedToInternet:
        return
          "The connection failed because the device is not connected to the internet"
      case .badRequest: return "Bad Request"
      case .authorizationFailed: return "Authorization Failed"
      case .forbidden:
        return
          "Access has been revoked. Please contact HyperTrack for more information."
      case .internalServerError: return "Internal Server Error"
      case .parsingError: return "JSON parsing error"
      case .locationPermissionsDenied:
        return "Access to Location services has not been authorized"
      case .locationServicesDisabled: return "Location service is disabled"
      case .activityPermissionsDenied:
        return "Access to Activity services has not been authorized"
      case .activityServicesDisabled: return "Activity services is disabled"
      case .serviceAlreadyRunning:
        return "Attempted to start a service which was already running"
      case .serviceAlreadyStopped:
        return "Attempted to stop a service which was already stopped"
      case .networkDisconnected: return "Network disconnected"
      case .networkDisconnectedGreater12Hours:
        return "Network disconnected greater then 12 hours."
      case .databaseReadFailed: return "Failed to read data from database"
      case .databaseWriteFailed: return "Failed to write data to database"
      case .sensorToDataMappingFailed:
        return "Failed to map sensor data to Event object"
      case .deviceIdBlank: return "DeviceId is blank"
      case .emptyResult: return "The result of this operation is empty."
      case .unknownService: return "Attempted to start access unknown service"
      case let .publishableKeyisNotSet(funcName):
        return "Attempt to \(funcName), before Publishable Key is set"
      case .invalidToken: return "Invalid token"
      case .emptyData: return "Name or matadata is empty"
      case .invalidMetadata: return "Invalid metadata"
      case .unknown: return "Something went wrong"
    }
  }
}

extension ErrorType: RawRepresentable {
  typealias RawValue = Int

  var rawValue: RawValue {
    switch self {
      case .badRequest: return 400
      case .authorizationFailed: return 401
      case .forbidden: return 403
      case .internalServerError: return 500
      case .urlErrorUnknown: return -998
      case .urlErrorCancelled: return -999
      case .urlErrorBadURL: return -1000
      case .urlErrorTimedOut: return -1001
      case .urlErrorUnsupportedURL: return -1002
      case .urlErrorCannotFindHost: return -1003
      case .urlErrorCannotConnectToHost: return -1004
      case .urlErrorNetworkConnectionLost: return -1005
      case .urlErrorNotConnectedToInternet: return -1009
      case .parsingError: return 98765
      case .locationPermissionsDenied: return 98766
      case .locationServicesDisabled: return 98767
      case .activityPermissionsDenied: return 98768
      case .activityServicesDisabled: return 98769
      case .serviceAlreadyRunning: return 98770
      case .serviceAlreadyStopped: return 98771
      case .networkDisconnected: return 98772
      case .networkDisconnectedGreater12Hours: return 98773
      case .databaseReadFailed: return 98774
      case .databaseWriteFailed: return 98775
      case .sensorToDataMappingFailed: return 98776
      case .deviceIdBlank: return 98777
      case .emptyResult: return 98778
      case .unknownService: return 98779
      case .publishableKeyisNotSet: return 98780
      case .invalidToken: return 98781
      case .emptyData: return 98782
      case .invalidMetadata: return 98783
      case .unknown: return 98784
    }
  }

  init(rawValue: RawValue) {
    switch rawValue {
      case 400: self = .badRequest
      case 401: self = .authorizationFailed
      case 403: self = .forbidden
      case 500 ..< 599: self = .internalServerError
      case -998: self = .urlErrorUnknown
      case -999: self = .urlErrorCancelled
      case -1000: self = .urlErrorBadURL
      case -1001: self = .urlErrorTimedOut
      case -1002: self = .urlErrorUnsupportedURL
      case -1003: self = .urlErrorCannotFindHost
      case -1004: self = .urlErrorCannotConnectToHost
      case -1005: self = .urlErrorNetworkConnectionLost
      case -1009: self = .urlErrorNotConnectedToInternet
      case 98765: self = .parsingError
      case 98766: self = .locationPermissionsDenied
      case 98767: self = .locationServicesDisabled
      case 98768: self = .activityPermissionsDenied
      case 98769: self = .activityServicesDisabled
      case 98770: self = .serviceAlreadyRunning
      case 98771: self = .serviceAlreadyStopped
      case 98772: self = .networkDisconnected
      case 98773: self = .networkDisconnectedGreater12Hours
      case 98774: self = .databaseReadFailed
      case 98775: self = .databaseWriteFailed
      case 98776: self = .sensorToDataMappingFailed
      case 98777: self = .deviceIdBlank
      case 98778: self = .emptyResult
      case 98779: self = .unknownService
      case 98780: self = .publishableKeyisNotSet("")
      case 98781: self = .invalidToken
      case 98782: self = .emptyData
      case 98783: self = .invalidMetadata
      default: self = .unknown
    }
  }
}
