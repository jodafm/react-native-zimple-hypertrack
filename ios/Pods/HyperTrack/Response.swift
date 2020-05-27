import Foundation

let emptyDataStatusCodes: Set<Int> = [204, 205]

final class Response {
  /// String representing JSON response data.
  var data: Data?

  /// HTTP status code of response.
  var statusCode: Int

  /// Response metadata.
  var response: HTTPURLResponse?

  /// Error representing an optional error.
  var error: SDKError?

  let result: Result<Data, SDKError>

  /**
   Initialize a Response object.

   - parameter data:     Data returned from server.
   - parameter response: Provides response metadata, such as HTTP headers and status code.
   - parameter error:    Indicates why the request failed, or nil if the request was successful.
   */
  init(
    data: Data?,
    statusCode: Int,
    response: HTTPURLResponse?,
    error: SDKError?
  ) {
    self.data = data
    self.response = response
    self.statusCode = statusCode
    self.error = error
    if let error = error {
      result = .failure(error)
    } else if let response = response,
      emptyDataStatusCodes.contains(response.statusCode)
    { result = .success(Data()) } else if let data = data {
      result = .success(data)
    } else { result = .failure(SDKError(.parsingError)) }
  }

  init() {
    data = nil
    response = nil
    statusCode = 400
    error = nil
    result = Result.failure(SDKError(.badRequest))
  }

  /**
   - returns: string representation of JSON data.
   */
  func toJSONString() -> String {
    guard let data = data else { return "" }
    return String(data: data, encoding: String.Encoding.utf8)!
  }
}
