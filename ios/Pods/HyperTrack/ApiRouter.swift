import Foundation

typealias Payload = [String: Any]
typealias DeviceId = String
typealias TimeDiff = Int

enum ApiRouter {
  case sendEvent([Payload])
  case sendCustomEvent(DeviceId, [Payload])
  case deviceRegister(DeviceId, Payload)
  case getToken(deviceId: String)
  case deviceSettings
}

enum ParamEncoding: Int {
  case url
  case json
  case gzip
}

extension ApiRouter: APIEndpoint {
  static var baseUrlString: String {
    return Provider.configManager.config.network.host
  }

  static var htBaseUrlString: String {
    return Provider.configManager.config.network.htBaseUrl
  }

  var host: String {
    switch self {
      case .deviceRegister, .getToken, .deviceSettings:
        return ApiRouter.htBaseUrlString
      default: return ApiRouter.baseUrlString
    }
  }

  var path: String {
    switch self {
      case .sendEvent: return "\(Provider.configManager.config.network.events)"
      case let .sendCustomEvent(result):
        return "\(Provider.configManager.config.network.customEvents)" + "/"
          + result.0
      case let .deviceRegister(result):
        return "\(Provider.configManager.config.network.registration)" + "/"
          + result.0
      case .deviceSettings:
        return "\(Provider.configManager.config.network.deviceSettings)"
      case .getToken:
        return "\(Provider.configManager.config.network.authenticate)"
    }
  }

  var params: Any? {
    switch self {
      case let .sendEvent(array): return array
      case let .sendCustomEvent(_, array): return array
      case let .deviceRegister(_, data): return data
      case .deviceSettings: return nil
      case let .getToken(deviceId):
        return ["device_id": deviceId, "scope": "generation"]
    }
  }

  var body: Data? {
    guard let params = params, encoding != .url else { return nil }
    switch encoding {
      case .json:
        do {
          return try JSONSerialization.data(
            withJSONObject: params,
            options: JSONSerialization.WritingOptions(rawValue: 0)
          )
        } catch { return nil }
      default: return nil
    }
  }

  var encoding: ParamEncoding {
    switch self {
      case .sendEvent, .sendCustomEvent, .deviceRegister, .getToken,
           .deviceSettings:
        return .json
    }
  }

  var method: HTTPMethod {
    switch self {
      case .sendEvent, .sendCustomEvent, .getToken: return .post
      case .deviceSettings: return .get
      case .deviceRegister: return .patch
    }
  }

  var headers: [String: String] {
    switch self {
      case .getToken:
        return [
          "Content-Type": "application/json",
          "Timezone": TimeZone.current.identifier,
          "Authorization":
            "Basic \(Data(Provider.appState.getPublishableKey().utf8).base64EncodedString(options: []))"
        ]
      default:
        return [
          "Content-Type": "application/json",
          "Timezone": TimeZone.current.identifier,
          "Authorization": "Bearer \(Provider.authManager.authToken?.token ?? "")"
        ]
    }
  }

  var retryIntervals: [Double] {
    switch self {
      default: return [4, 9, 16]
    }
  }
}
