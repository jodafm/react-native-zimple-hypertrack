import Foundation

// MARK: - Metadata

/// An object  that represents a valid metadata.
///
/// Currently being a valid JSON is the only requirement for HTMetadata, but
/// new requirements can be added in the future.
@objcMembers public final class HTMetadata: NSObject {
  let metadata: HyperTrack.Metadata

  @nonobjc init(metadata: HyperTrack.Metadata) {
    self.metadata = metadata
  }

  /// Creates an empty metadata.
  public convenience override init() {
    self.init(metadata: HyperTrack.Metadata())
  }

  /// Creates metadata from a Dictonary type.
  ///
  /// - Parameter dictionary: A key-value dictionary containing types
  ///   representable in JSON.
  public convenience init?(dictionary: [String: Any]) {
    if let metadata = HyperTrack.Metadata(dictionary: dictionary) {
      self.init(metadata: metadata)
    } else {
      return nil
    }
  }

  /// Creates a Metadata value from a JSON string.
  ///
  /// - Parameter jsonString: A string that can be serialized to JSON.
  public convenience init?(jsonString: String) {
    if let metadata = HyperTrack.Metadata(jsonString: jsonString) {
      self.init(metadata: metadata)
    } else {
      return nil
    }
  }
}

// MARK: - SDK

/// An interface for HyperTrack SDK.
@objcMembers public final class HTSDK: NSObject {
  /// A notification name used for notifications emitted when SDK starts
  /// tracking.
  ///
  /// Subscribe to this notification to update the UI or trigger custom business
  /// logic.
  ///
  /// It's emitted when SDK records location events. If there is a stop tracking
  /// event or error, `stoppedTrackingNotification` will be emitted. Every
  /// `startedTrackingNotification` will have a corresponding
  /// `stoppedTrackingNotification`
  public static let startedTrackingNotification = NSNotification.Name(
    "HyperTrackStartedTracking"
  )

  /// A notification name used for notifications emitted when SDK stops
  /// tracking.
  ///
  /// Subscribe to this notification to update the UI or trigger custom business
  /// logic.
  ///
  /// It's emitted when SDK stops recording location events for any reason.
  public static let stoppedTrackingNotification = NSNotification.Name(
    "HyperTrackStoppedTracking"
  )

  /// A notification name used for notifications emitted when SDK encounters a
  /// restorable error.
  ///
  /// Subscribe to this notification to update the UI or trigger custom business
  /// logic.
  ///
  /// This notication can be emitted when SDK is tracking or is asked to track,
  /// but something blocks it.
  ///
  /// If this notification is emitted, SDK will start tracking again after the
  /// blocker is gone and if there was no command to stop during the blocker.
  ///
  /// Any attempt to start tracking during the blocker will re-emit this
  /// notification.
  ///
  /// - Note: Check `HTRestorableError` enum to see all types of errors emitted
  ///   by this notification.
  public static let didEncounterRestorableErrorNotification = NSNotification
    .Name(
      "HyperTrackDidEncounterRestorableError"
    )

  /// A notification name used for notifications emitted when SDK encounters an
  /// unrestorable error.
  ///
  /// Subscribe to this notification to update the UI or trigger custom business
  /// logic.
  ///
  /// This notification can be emitted when SDK is tracking or is asked to
  /// track, but something blocks it.
  ///
  /// If this notification is emitted, SDK won't start tracking until the app is
  /// restarted.
  ///
  /// Any subsequent attempt to start tracking will re-emit this notification.
  ///
  /// - Note: Check `HTUnrestorableError` enum to see all types of errors
  ///   emitted by this notification.
  public static let didEncounterUnrestorableErrorNotification =
    NSNotification.Name("HyperTrackDidEncounterUnrestorableError")

  /// A string used to identify a device uniquely.
  ///
  /// `deviceID` is stored on disk and is consistent between app runs, but every
  /// app reinstall will result in a new `deviceID`.
  public let deviceID: String
  let hyperTrack: HyperTrack

  /// Creates an interface for the SDK.
  ///
  /// Multiple interfaces can be created without duplicating memory and
  /// resources.
  ///
  /// - Note: Use `makeSDKWithPublishableKey:` factory method if you need an
  ///   explicit error handling using `HTResult` type.
  ///
  /// - Parameter publishableKey: a non-empty string of  publishable key
  ///   provided in HyperTrack's dashboard
  ///   [setup page](https://dashboard.hypertrack.com/setup).
  public convenience init?(publishableKey: String) {
    if let publishableKey = HyperTrack.PublishableKey(publishableKey), let hyperTrack = try? HyperTrack(
      publishableKey: publishableKey
    ) {
      self.init(hyperTrack: hyperTrack)
    } else {
      return nil
    }
  }

  init(hyperTrack: HyperTrack) {
    deviceID = hyperTrack.deviceID
    self.hyperTrack = hyperTrack
  }

  /// Creates and returns an SDK interface or `HTFatalError` if there are
  /// blockers to successful initialization.
  ///
  /// Multiple interfaces can be created without duplicating memory and
  /// resources.
  ///
  /// - Note: Use initializer `initWithPublishableKey:` if you
  ///   don't need to handle errors explicitly.
  ///
  /// - Parameter publishableKey: a non-empty string of  publishable key
  ///   provided in HyperTrack's dashboard
  ///   [setup page](https://dashboard.hypertrack.com/setup).
  ///
  /// - Returns: An `HTResult` with an instance for HyperTrack SDK or an error
  ///   of type `HTFatalError` if there is a development or production blocker
  ///   to SDK initialization.
  public static func makeSDK(publishableKey: String) -> HTResult {
    if publishableKey.isEmpty {
      return HTResult(hyperTrack: nil, error: errorPublishableKey())
    }
    switch HyperTrack.makeSDK(
      publishableKey: HyperTrack.PublishableKey(publishableKey)!
    ) {
      case let .success(hyperTrack):
        return HTResult(hyperTrack: HTSDK(hyperTrack: hyperTrack), error: nil)
      case let .failure(error):
        return HTResult.fromSwiftFatalError(fatalError: error)
    }
  }

  /// Reflects tracking intent.
  ///
  /// When SDK receives start command either using `start` method, silent
  /// push notification, or with `syncDeviceSettings`, it captures this
  /// intent. SDK tries to track until it receives a stop command through the
  /// means described above or if it encounters one of the following errors:
  /// `HTUnrestorableErrorInvalidPublishableKey`,
  /// `HTRestorableErrorTrialEnded`, `HTRestorableErrorPaymentDefault`.
  ///
  /// - Note: `isRunning` only reflects an intent to track, not the actual
  /// location tracking status. Location tracking can be blocked by a lack of
  /// permissions or other conditions, but if there is an intent to track, it
  /// will resume once those blockers are resolved. Use notifications if you
  /// need to react to location tracking status.
  public var isRunning: Bool {
    return hyperTrack.isRunning
  }

  /// Sets the device name for the current device.
  ///
  /// You can see the device name in the devices list in the Dashboard or
  /// through APIs.
  ///
  /// - Parameter deviceName: A human-readable string describing a device or its
  ///   user.
  public func setDeviceName(_ deviceName: String) {
    hyperTrack.setDeviceName(deviceName)
  }

  /// Sets the device metadata for the current device.
  ///
  /// You can see the device metadata in device view in Dashboard or through
  /// APIs. Metadata can help you identify devices with your internal entities
  /// (for example, users and their IDs).
  ///
  /// - Parameter metadata: A Metadata struct that represents a valid JSON
  ///   object.
  public func setDeviceMetadata(_ metadata: HTMetadata) {
    hyperTrack.setDeviceMetadata(metadata.metadata)
  }

  /// Expresses an intent to start location tracking.
  ///
  /// If something is blocking the SDK from tracking (for example, the user
  /// didn't grant location permissions), the appropriate notification with the
  /// corresponding error will be emitted. The SDK immediately starts tracking
  /// when blockers are resolved (when user grant the permissions), no need for
  /// another `start` invocation when that happens. This intent survives app
  /// restarts.
  public func start() {
    hyperTrack.start()
  }

  /// Stops location tracking immediately.
  public func stop() {
    hyperTrack.stop()
  }

  /// Synchronizes device settings with HyperTrack's platform.
  ///
  /// If you are using silent push notifications to start and end trips, this
  /// method can be used as a backup when push notification delivery fails.
  /// Place it in AppDelegate and additionally on screens where you expect
  /// tracking to start (screens that trigger subsequent tracking, screens after
  /// user login, etc.).
  public func syncDeviceSettings() {
    hyperTrack.syncDeviceSettings()
  }

  /// Adds a new trip marker.
  ///
  /// Use trip markers to mark a location at the current timestamp with
  /// metadata. This marker can represent any custom event in your system that
  /// you want to attach to location data (a moment when the delivery completed,
  /// a worker checking in, etc.).
  ///
  /// - Note: Actual data is sent to servers when conditions are optimal. Calls
  ///   made to this API during an internet outage will be recorded and sent
  ///   when the connection is available.
  ///
  /// - Parameter marker: A Metadata struct that represents a valid JSON
  ///   object.
  public func addTripMarker(_ marker: HTMetadata) {
    hyperTrack.addTripMarker(marker.metadata)
  }

  /// Registers for silent push notifications.
  ///
  /// Call this method in `application:didFinishLaunchingWithOptions:)`.
  public static func registerForRemoteNotifications() {
    HyperTrack.registerForRemoteNotifications()
  }

  /// Updates device token for the current device.
  ///
  /// Call this method to handle successful remote notification registration
  /// in `application:didRegisterForRemoteNotificationsWithDeviceToken:`
  ///
  /// - Parameter deviceToken: The device token passed to
  /// `application:didRegisterForRemoteNotificationsWithDeviceToken:`.
  public static func didRegisterForRemoteNotificationsWithDeviceToken(
    _ deviceToken: Data
  ) {
    HyperTrack.didRegisterForRemoteNotificationsWithDeviceToken(deviceToken)
  }

  /// Tranfers the registration error to HyperTrack SDK.
  ///
  /// Call this method to handle unsuccessful remote notification registration
  /// in `application:didFailToRegisterForRemoteNotificationsWithError:`
  ///
  /// - Parameter error: The error object passed to
  ///   `application:didFailToRegisterForRemoteNotificationsWithError:`
  public static func didFailToRegisterForRemoteNotificationsWithError(
    _ error: Error
  ) {
    HyperTrack.didFailToRegisterForRemoteNotificationsWithError(error)
  }

  /// Tranfers the silent push notification to HyperTrack SDK.
  ///
  /// Call this method to handle a silent push notification in
  /// `application:didReceiveRemoteNotification:fetchCompletionHandler:`
  ///
  /// - Note: SDK ignores push notifications meant for your app, but if you want
  ///   to make sure it doesn't receive them use "hypertrack" key inside the
  ///   `userInfo` object:
  ///
  ///       if (userInfo[@"hypertrack"] != nil) {
  ///           // This is HyperTrack's notification
  ///           [HTSDK didReceiveRemoteNotification: userInfo
  ///                        fetchCompletionHandler: completionHandler];
  ///       } else {
  ///           // Handle your server's notification here
  ///       }
  ///
  /// - Parameters:
  ///     - userInfo: The `userInfo` dictionary passed to
  ///       `application:didReceiveRemoteNotification:fetchCompletionHandler:)`
  ///     - completionHandler: The handler function passed to
  ///       `application:didReceiveRemoteNotification:fetchCompletionHandler:`
  public static func didReceiveRemoteNotification(
    _ userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (
      UIBackgroundFetchResult
    ) -> Void
  ) {
    HyperTrack.didReceiveRemoteNotification(
      userInfo,
      fetchCompletionHandler: completionHandler
    )
  }
}

// MARK: - Errors

@objc public extension NSError {
  static let HTFatalErrorDomain: String = "HTFatalErrorDomain"
  static let HTRestorableErrorDomain: String = "HTRestorableErrorDomain"
  static let HTUnrestorableErrorDomain: String = "HTUnrestorableErrorDomain"
}

func error(domain: String) -> (_ code: Int, _ message: String) -> NSError {
  return { code, message in
    NSError(
      domain: domain,
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

/// A grouping of errors that can be emitted during initialization.
@objc public enum HTFatalError: Int {
  /// Publishable Key cannot be an empty string.
  case developmentPublishableKeyIsEmpty = -4110

  /// "Location updates" mode is not set in your target's "Signing &
  /// Capabilities".
  case developmentMissingLocationUpdatesBackgroundModeCapability = -4111

  /// You are running the SDK on the iOS simulator, which currently does not
  /// support CoreMotion services. You can test the SDK on real iOS devices
  /// only.
  case developmentRunningOnSimulatorUnsupported = -4112

  /// The device doesn't have GPS capabilities, or it is malfunctioning.
  case productionLocationServicesUnavalible = -4121

  /// The device doesn't have Motion capabilities, or it is malfunctioning.
  case productionMotionActivityServicesUnavalible = -4122

  /// Motion activity permissions denied before SDK initialization. Granting
  /// them will restart the app, so in effect, they are denied during this app's
  /// session.
  case productionMotionActivityPermissionsDenied = -4123
}

func errorPublishableKey() -> NSError {
  return error(domain: NSError.HTFatalErrorDomain)(
    HTFatalError.developmentPublishableKeyIsEmpty.rawValue,
    "Publishable Key cannot be an empty string."
  )
}

func errorFromFatalError(_ fatalError: HyperTrack.FatalError) -> NSError {
  let fatalErrorDomain = error(domain: NSError.HTFatalErrorDomain)

  switch fatalError {
    case let .developmentError(developmentError):
      switch developmentError {
        case .missingLocationUpdatesBackgroundModeCapability:
          return fatalErrorDomain(
            HTFatalError.developmentMissingLocationUpdatesBackgroundModeCapability.rawValue,
            #""Location updates" mode is not set in your target's "Signing & Capabilities"."#
          )
        case .runningOnSimulatorUnsupported:
          return fatalErrorDomain(
            HTFatalError.developmentRunningOnSimulatorUnsupported.rawValue,
            "You are running the SDK on the iOS simulator, which currently does not support CoreMotion services. You can test the SDK on real iOS devices only."
          )
      }
    case let .productionError(productionError):
      switch productionError {
        case .locationServicesUnavalible:
          return fatalErrorDomain(
            HTFatalError.productionLocationServicesUnavalible.rawValue,
            "The device doesn't have GPS capabilities, or it is malfunctioning."
          )
        case .motionActivityServicesUnavalible:
          return fatalErrorDomain(
            HTFatalError.productionMotionActivityServicesUnavalible.rawValue,
            "The device doesn't have Motion capabilities, or it is malfunctioning."
          )
        case .motionActivityPermissionsDenied:
          return fatalErrorDomain(
            HTFatalError.productionMotionActivityPermissionsDenied.rawValue,
            "Motion activity permissions denied before SDK initialization. Granting them will restart the app, so in effect, they are denied during this app's session."
          )
      }
  }
}

/// An error encountered during location tracking, after which the SDK can
/// restore tracking location during this app's session.
@objc public enum HTRestorableError: Int {
  /// The user denied location permissions.
  case locationPermissionsDenied = -4200

  /// The user disabled location services systemwide.
  case locationServicesDisabled = -4201

  /// The user disabled motion services systemwide.
  case motionActivityServicesDisabled = -4202

  /// There was no network connection for 12 hours.
  ///
  /// SDK stops collecting location data after 12 hours without a network
  /// connection. It automatically resumes tracking after the connection is
  /// restored.
  case networkConnectionUnavailable = -4203

  /// HyperTrack's trial period has ended.
  case trialEnded = -4204

  /// There was an error processing your payment.
  case paymentDefault = -4205
}

func errorFromRestorableError(
  _ restorableError: HyperTrack.RestorableError
) -> NSError {
  let restorableErrorDomain = error(domain: NSError.HTRestorableErrorDomain)

  switch restorableError {
    case .locationPermissionsDenied:
      return restorableErrorDomain(
        HTRestorableError.locationPermissionsDenied.rawValue,
        "The user denied location permissions."
      )
    case .locationServicesDisabled:
      return restorableErrorDomain(
        HTRestorableError.locationServicesDisabled.rawValue,
        "The user disabled location services systemwide."
      )
    case .motionActivityServicesDisabled:
      return restorableErrorDomain(
        HTRestorableError.motionActivityServicesDisabled.rawValue,
        "The user disabled motion services systemwide."
      )
    case .networkConnectionUnavailable:
      return restorableErrorDomain(
        HTRestorableError.networkConnectionUnavailable.rawValue,
        "There was no network connection for 12 hours."
      )
    case .trialEnded:
      return restorableErrorDomain(
        HTRestorableError.trialEnded.rawValue,
        "HyperTrack's trial period has ended."
      )
    case .paymentDefault:
      return restorableErrorDomain(
        HTRestorableError.paymentDefault.rawValue,
        "There was an error processing your payment."
      )
  }
}

@objc public enum HTUnrestorableError: Int {
  /// Publishable Key wan't found in HyperTrack's database.
  ///
  /// This error shouldn't happen in production, but due to its asynchronous
  /// nature, it can be detected only during tracking. SDK stops all functions
  /// until the app is recompiled with the correct Publishable Key.
  case invalidPublishableKey = -4300

  /// Motion activity permissions denied after SDK's initialization. Granting
  /// them will restart the app, so in effect, they are denied during this app's
  /// session.
  case motionActivityPermissionsDenied = -4301
}

func errorFromUnrestorableError(
  _ unrestorableError: HyperTrack.UnrestorableError
) -> NSError {
  let unrestorableErrorDomain = error(domain: NSError.HTUnrestorableErrorDomain)

  switch unrestorableError {
    case .invalidPublishableKey:
      return unrestorableErrorDomain(
        HTUnrestorableError.invalidPublishableKey.rawValue,
        "Publishable Key wan't found in HyperTrack's database."
      )
    case .motionActivityPermissionsDenied:
      return unrestorableErrorDomain(
        HTUnrestorableError.motionActivityPermissionsDenied.rawValue,
        "Motion activity permissions denied after SDK's initialization. Granting them will restart the app, so in effect, they are denied during this app's session."
      )
  }
}

// MARK: - Result

@objcMembers public final class HTResult: NSObject {
  public let hyperTrack: HTSDK?
  public let error: NSError?

  init(hyperTrack: HTSDK?, error: NSError?) {
    self.hyperTrack = hyperTrack
    self.error = error
  }

  static func fromSwiftFatalError(fatalError: HyperTrack.FatalError) -> HTResult {
    return HTResult(hyperTrack: nil, error: errorFromFatalError(fatalError))
  }
}

// MARK: Notifications

@objc public extension NSNotification {
  /// A convenience function that recovers either `HTRestorableError` or
  /// `HTUnrestorableError` from a Notification. Use this function if you are
  /// subscribed to both notifications in the same selector.
  func hyperTrackTrackingError() -> NSError? {
    if let trackingError = (self as Notification).hyperTrackTrackingError() {
      switch trackingError {
        case let .restorableError(restorableError):
          return errorFromRestorableError(restorableError)
        case let .unrestorableError(unrestorableError):
          return errorFromUnrestorableError(unrestorableError)
      }
    }
    return nil
  }

  /// A convenience function that recovers the `HTRestorableError` from
  /// Notification.
  func hyperTrackRestorableError() -> NSError? {
    if let restorableError = (self as Notification).hyperTrackRestorableError() {
      return errorFromRestorableError(restorableError)
    }
    return nil
  }

  /// A convenience function that recovers the `HTUnrestorableError` from
  /// Notification.
  func hyperTrackUnrestorableError() -> NSError? {
    if let unrestorableError = (self as Notification).hyperTrackUnrestorableError() {
      return errorFromUnrestorableError(unrestorableError)
    }
    return nil
  }
}
