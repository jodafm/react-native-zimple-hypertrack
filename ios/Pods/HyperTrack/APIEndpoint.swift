import Foundation

enum HTTPMethod: String {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case head = "HEAD"
}

protocol APIEndpoint {
  var body: Data? { get }
  var headers: [String: String] { get }
  var host: String { get }
  var method: HTTPMethod { get }
  var path: String { get }
  var params: Any? { get }
  var encoding: ParamEncoding { get }
  var retryIntervals: [Double] { get }
}

extension APIEndpoint {
  var body: Data? { return nil }

  var params: Any? { return nil }

  var headers: [String: String] { return [:] }

  var baseURL: String { return host }

  var url: URL {
    var components = URLComponents(string: baseURL)
    components?.path = path
    if method == .get, let params = params as? Payload {
      components?.queryItems = params.map {
        URLQueryItem(name: $0.key, value: $0.value as? String)
      }
    }
    guard let url = components?.url else {
      let failureReason =
      "Failed to construct URL from components: \(String(describing: components))"
      logNetwork.fault(failureReason)
      preconditionFailure(failureReason)
    }
    return url
  }
}
