import Foundation

final class Request {
  let id: String
  private weak var session: URLSession?
  let endpoint: APIEndpoint
  private(set) var urlRequest: URLRequest
  private var numberOfRetries: Int
  let maxRetryCount: Int

  init?(
    id: String,
    session: URLSession?,
    endpoint: APIEndpoint,
    retryCount: Int
  ) {
    self.id = id
    urlRequest = URLRequest(url: endpoint.url)
    urlRequest.httpMethod = endpoint.method.rawValue
    urlRequest.httpBody = endpoint.body

    self.session = session
    self.endpoint = endpoint
    numberOfRetries = 0
    maxRetryCount = retryCount
  }

  func getNextTime(
    error: SDKError,
    counter: Int,
    maxRetryCount: Int,
    endpoint: APIEndpoint
  ) -> Double? {
    if !error.isServerError || !error.isAuthorizationFailed { return nil }

    let intervals = endpoint.retryIntervals
    if counter < intervals.count, counter >= 0, counter < maxRetryCount {
      return intervals[counter]
    } else { return nil }
  }

  private func addHeaders() {
    for (header, value) in endpoint.headers {
      urlRequest.setValue(value, forHTTPHeaderField: header)
    }
  }

  func execute(_ completion: @escaping (_ response: Response) -> Void) {
    guard let session = session else { return }
    addHeaders()

    logRequest.log("Executing request: \(prettyPrintURLRequest(urlRequest))")

    let task = session.dataTask(
      with: urlRequest,
      completionHandler: { [weak self] data, response, error in
        guard let self = self else { return }
        let httpResponse: HTTPURLResponse? = response as? HTTPURLResponse
        var statusCode: Int = 0
        var htError: SDKError?

        // Handle HTTP errors.
        errorCheck: if let httpResponse = httpResponse {
          statusCode = httpResponse.statusCode

          if statusCode <= 299 { break errorCheck }
          if statusCode == 403, let data = data,
            let errorPayload = try? JSONSerialization.jsonObject(
              with: data,
              options: []
            ) as? [String: String], let payload = errorPayload,
            let errorMessage = payload["error"] {
            htError = SDKError(
              ErrorType(rawValue: statusCode),
              message: errorMessage
            )
          } else { htError = SDKError(code: statusCode) }
          logResponse.error(
            "Failed to execute the request: \(prettyPrintURLRequest(self.urlRequest)) with error: \(prettyPrintSDKError(htError))"
          )
        }

        // Any other errors.
        if (response == nil && !emptyDataStatusCodes.contains(statusCode))
          || error != nil {
          if let errorCode = error?._code {
            htError = SDKError(code: errorCode)
          } else { htError = SDKError(.unknown) }
          logResponse.error(
            "Failed to execute the request: \(prettyPrintURLRequest(self.urlRequest)) with error: \(prettyPrintSDKError(htError))"
          )
        }
        if let error = htError,
          let delay = self.getNextTime(
            error: error,
            counter: self.numberOfRetries,
            maxRetryCount: self.maxRetryCount,
            endpoint: self.endpoint
          ), delay > 0 {
          self.numberOfRetries += 1
          logNetwork.log(
            "Retry number: \(self.numberOfRetries) of executing a request: \(prettyPrintURLRequest(self.urlRequest))"
          )
          DispatchQueue.global(qos: DispatchQoS.QoSClass.default).asyncAfter(
            deadline: .now() + delay,
            execute: { [weak self] in self?.execute(completion) }
          )
        } else {
          let response = Response(
            data: data,
            statusCode: statusCode,
            response: httpResponse,
            error: htError
          )
          if let error = response.error {
            logResponse.error(
              "Failed to execute the request: \(prettyPrintURLRequest(self.urlRequest)) with error: \(prettyPrintSDKError(error))"
            )
          }
          logResponse.log(
            "Executed the request: \(prettyPrintURLRequest(self.urlRequest)) with response: \(prettyPrintResponse(response))"
          )
          completion(response)
        }
      }
    )
    task.resume()
  }
}
