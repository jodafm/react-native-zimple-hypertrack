import enum UIKit.UIBackgroundFetchResult

/// Adds support for Xcode 10.1 that doesn't have Swift 5 compiler and new
/// Result type
#if !compiler(>=5.0)
  public enum Result<Success, Failure> where Failure: Error {
    case success(Success)
    case failure(Failure)
  }
#endif

// MARK: - API

/// An interface for HyperTrack SDK.
public final class HyperTrack {
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
  public static let startedTrackingNotification = Notification.Name(
    "HyperTrackStartedTracking"
  )

  /// A notification name used for notifications emitted when SDK stops
  /// tracking.
  ///
  /// Subscribe to this notification to update the UI or trigger custom business
  /// logic.
  ///
  /// It's emitted when SDK stops recording location events for any reason.
  public static let stoppedTrackingNotification = Notification.Name(
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
  /// - Note: Check `RestorableError` enum to see all types of errors emitted by
  ///   this notification.
  public static let didEncounterRestorableErrorNotification = Notification.Name(
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
  /// - Note: Check `UnrestorableError` enum to see all types of errors emitted
  ///   by this notification.
  public static let didEncounterUnrestorableErrorNotification =
    Notification.Name("HyperTrackDidEncounterUnrestorableError")

  /// A string used to identify a device uniquely.
  ///
  /// `deviceID` is stored on disk and is consistent between app runs, but every
  /// app reinstall will result in a new `deviceID`.
  public let deviceID: String

  /// Creates an interface for the SDK.
  ///
  /// Multiple interfaces can be created without duplicating memory and
  /// resources.
  ///
  /// - Note: Use `makeSDK(publishableKey:)` factory method if you need an
  ///   explicit and type-safe error handling using `Result` type.
  ///
  /// - Parameter publishableKey: struct containing a non-empty string of
  ///   publishable key provided in HyperTrack's dashboard
  ///   [setup page](https://dashboard.hypertrack.com/setup).
  ///
  /// - Throws: An error of type `FatalError` if there is a development or
  ///   production blocker to SDK initialization.
  public init(publishableKey: PublishableKey) throws {
    logInterface.log(
      "Initializing SDK \(getSDKVersion()) with publishableKey: \(publishableKey.publishableKey)"
    )
    Core.shared.setup()
    Core.shared.savePublishableKey(publishableKey.publishableKey)
    if let error = checkForFatalErrors() {
      logInterface.fault("Failed to initialize SDK with error: \(error)")
      throw error
    } else {
      self.deviceID = Core.shared.deviceIdentifier.uuidString
      Core.shared.setPublishableKey()
    }
  }

  /// Creates and returns an SDK interface or `FatalError` if there are blockers
  /// to successful initialization.
  ///
  /// Multiple interfaces can be created without duplicating memory and
  /// resources.
  ///
  /// - Note: Use throwing initializer `init(publishableKey:) throws` if you
  ///   don't need to handle errors explicitly or error type-safety is not
  ///   critical.
  ///
  /// - Parameter publishableKey: struct containing a non-empty string of
  ///   publishable key provided in HyperTrack's dashboard
  ///   [setup page](https://dashboard.hypertrack.com/setup).
  ///
  /// - Returns: A Result with an instance for HyperTrack SDK or an error of
  ///   type `FatalError` if there is a development or production blocker to SDK
  ///   initialization.
  public static func makeSDK(publishableKey: PublishableKey) -> Result<
    HyperTrack, FatalError
  > {
    do { return .success(try HyperTrack(publishableKey: publishableKey)) } catch
    { return .failure(error as! FatalError) }
  }

  /// Reflects tracking intent.
  ///
  /// When SDK receives start command either using `start()` method, silent
  /// push notification, or with `syncDeviceSettings()`, it captures this
  /// intent. SDK tries to track until it receives a stop command through the
  /// means described above or if it encounters one of the following errors:
  /// `UnrestorableError.invalidPublishableKey`, `RestorableError.trialEnded`,
  /// `RestorableError.paymentDefault`.
  ///
  /// - Note: `isRunning` only reflects an intent to track, not the actual
  /// location tracking status. Location tracking can be blocked by a lack of
  /// permissions or other conditions, but if there is an intent to track, it
  /// will resume once those blockers are resolved. Use notifications if you
  /// need to react to location tracking status.
  public var isRunning: Bool {
    let isRunning = Core.shared.isTracking
    logInterface.log("Computing HyperTrack.isRunning: \(isRunning)")
    return isRunning
  }

  /// Sets the device name for the current device.
  ///
  /// You can see the device name in the devices list in the Dashboard or
  /// through APIs.
  ///
  /// - Parameter deviceName: A human-readable string describing a device or its
  ///   user.
  public func setDeviceName(_ deviceName: String) {
    logInterface.log("Setting HyperTrack.deviceName: \(deviceName)")
    Core.shared.setName(deviceName)
  }

  /// Sets the device metadata for the current device.
  ///
  /// You can see the device metadata in device view in Dashboard or through
  /// APIs. Metadata can help you identify devices with your internal entities
  /// (for example, users and their IDs).
  ///
  /// - Parameter metadata: A Metadata struct that represents a valid JSON
  ///   object.
  public func setDeviceMetadata(_ metadata: Metadata) {
    logInterface.log(
      "Setting HyperTrack.metadata: \(metadata.rawValue as AnyObject)"
    )
    Core.shared.setMetadata(metadata)
  }

  /// Expresses an intent to start location tracking.
  ///
  /// If something is blocking the SDK from tracking (for example, the user
  /// didn't grant location permissions), the appropriate notification with the
  /// corresponding error will be emitted. The SDK immediately starts tracking
  /// when blockers are resolved (when user grant the permissions), no need for
  /// another `start()` invocation when that happens. This intent survives app
  /// restarts.
  public func start() {
    logInterface.log("Starting traking")
    Core.shared.startTracking()
  }

  /// Stops location tracking immediately.
  public func stop() {
    logInterface.log("Stopping traking")
    Core.shared.stopTracking()
  }

  /// Synchronizes device settings with HyperTrack's platform.
  ///
  /// If you are using silent push notifications to start and end trips, this
  /// method can be used as a backup when push notification delivery fails.
  /// Place it in AppDelegate and additionally on screens where you expect
  /// tracking to start (screens that trigger subsequent tracking, screens after
  /// user login, etc.).
  public func syncDeviceSettings() {
    logInterface.log("Syncing device settings")
    Core.shared.syncDeviceSettings()
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
  public func addTripMarker(_ marker: Metadata) {
    logInterface.log(
      "Adding trip marker with marker: \(marker.rawValue as AnyObject)"
    )
    Core.shared.setTripMarker(marker)
  }

  /// Registers for silent push notifications.
  ///
  /// Call this method in
  /// `application(_:didFinishLaunchingWithOptions:launchOptions:)`
  public static func registerForRemoteNotifications() {
    logInterface.log("Registering for remote notifications")
    registerForSilentPushNotifications()
  }

  /// Updates device token for the current device.
  ///
  /// Call this method to handle successful remote notification registration
  /// in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
  ///
  /// - Parameter deviceToken: The device token passed to
  /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
  public static func didRegisterForRemoteNotificationsWithDeviceToken(
    _ deviceToken: Data
  ) {
    let token = parseDeviceToken(deviceToken)
    logInterface.log(
      "Registered for remote notifications with device token: \(token)"
    )
    registerForSilentPushNotificationsWithDeviceToken(token, Provider.appState)
  }

  /// Tranfers the registration error to HyperTrack SDK.
  ///
  /// Call this method to handle unsuccessful remote notification registration
  /// in `application(_:didFailToRegisterForRemoteNotificationsWithError:)`
  ///
  /// - Parameter error: The error object passed to
  ///   `application(_:didFailToRegisterForRemoteNotificationsWithError:)`
  public static func didFailToRegisterForRemoteNotificationsWithError(
    _ error: Error
  ) {
    logInterface.error(
      "Failed to register for remote notifications with error: \(error)"
    )
    didFailToRegisterForSilentPushNotificationsWithError(
      error,
      Provider.appState
    )
  }

  /// Tranfers the silent push notification to HyperTrack SDK.
  ///
  /// Call this method to handle a silent push notification in
  /// `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
  ///
  /// - Note: SDK ignores push notifications meant for your app, but if you want
  ///   to make sure it doesn't receive them use "hypertrack" key inside the
  ///   `userInfo` object:
  ///
  ///       if userInfo["hypertrack"] != nil {
  ///           // This is HyperTrack's notification
  ///           HyperTrack.didReceiveRemoteNotification(
  ///               userInfo,
  ///               fetchCompletionHandler: completionHandler)
  ///       } else {
  ///           // Handle your server's notification here
  ///       }
  ///
  /// - Parameters:
  ///     - userInfo: The `userInfo` dictionary passed to
  ///       `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
  ///     - completionHandler: The handler function passed to
  ///       `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
  public static func didReceiveRemoteNotification(
    _ userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (
      UIBackgroundFetchResult
    ) -> Void
  ) {
    logInterface.log(
      "Did receive remote notification: \(userInfo as AnyObject)"
    )
    receiveSilentPushNotification(
      userInfo,
      Provider.appState,
      completionHandler: completionHandler
    )
  }

  // MARK: - Publishable Key

  /// A compile-time guaranteed non-empty Publishable Key string.
  ///
  /// Copy the Publishable Key string from HyperTrack's dashboard
  /// [setup page](https://dashboard.hypertrack.com/setup)
  public struct PublishableKey {
    let publishableKey: String

    /// Creates a Publishable Key in the same way as `URL.init(string:)` from
    /// Foundation.
    ///
    ///     HyperTrack(publishableKey: .init("Your_Publishable_Key")!)
    ///
    /// - Parameter publishableKey: Your Publishable Key string.
    public init?(_ publishableKey: String) {
      if publishableKey.isEmpty { return nil }
      self.publishableKey = publishableKey
    }

    /// Creates a Publishable Key in a type-safe way without the need for
    /// force-unwrap. Place the first letter of your Publishable Key in the
    /// `firstCharacter` argument and the rest of the key in the `restOfTheKey`
    /// argument.
    ///
    ///     HyperTrack(publishableKey: .init("Y", "our_Publishable_Key"))
    ///
    /// - Parameters:
    ///     - firstCharacter: The first character of your Publishable Key
    ///       string.
    ///     - restOfTheKey: The rest of your Publishable Key string.
    public init(_ firstCharacter: Character, _ restOfTheKey: String) {
      self.publishableKey = String(firstCharacter) + restOfTheKey
    }
  }

  // MARK: - Metadata

  /// A structure  that represents a valid metadata.
  ///
  /// Currently being a valid JSON is the only requirement for Metadata, but
  /// new requirements can be added in the future.
  public struct Metadata: RawRepresentable {
    public typealias RawValue = [String: Any]

    public let rawValue: RawValue

    /// Creates an empty metadata.
    public init() { rawValue = [:] }

    public init?(rawValue: RawValue) {
      if HyperTrack.Metadata.isDictionaryJSONSerializable(rawValue) {
        self.rawValue = rawValue
      } else { return nil }
    }

    /// Creates metadata from a Dictonary type.
    ///
    /// - Parameter dictionary: A key-value dictionary containing types
    ///   representable in JSON.
    public init?(dictionary: [String: Any]) {
      if HyperTrack.Metadata.isDictionaryJSONSerializable(dictionary) {
        self.rawValue = dictionary
      } else { return nil }
    }

    /// Creates a Metadata value from a JSON string.
    ///
    /// - Parameter jsonString: A string that can be serialized to JSON.
    public init?(jsonString: String) {
      if let data = jsonString.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(
          with: data,
          options: .allowFragments
        ) as? [String: Any], let unwrappedJSON = json
      { self.rawValue = unwrappedJSON } else {
        return nil
      }
    }

    static func isDictionaryJSONSerializable(_ dictionary: [String: Any])
      -> Bool {
      if JSONSerialization.isValidJSONObject(dictionary),
        let _ = try? JSONSerialization.data(
          withJSONObject: dictionary,
          options: JSONSerialization.WritingOptions(rawValue: 0)
        )
      { return true } else { return false }
    }
  }

  // MARK: - Errors

  /// A grouping of errors that can be emitted during initialization.
  public enum FatalError: Error {
    case developmentError(DevelopmentError)
    case productionError(ProductionError)

    /// A convenience property to retrieve `DevelopmentError` associated enum.
    public var developmentError: DevelopmentError? {
      guard case let .developmentError(value) = self else { return nil }
      return value
    }

    /// A convenience property to retrieve `ProductionError` associated enum.
    public var productionError: ProductionError? {
      guard case let .productionError(value) = self else { return nil }
      return value
    }
  }

  /// Errors that can be emitted during the development and integration of the
  /// SDK.
  ///
  /// Those errors should be resolved before going to production.
  public enum DevelopmentError: Error {
    /// "Location updates" mode is not set in your target's "Signing &
    /// Capabilities".
    case missingLocationUpdatesBackgroundModeCapability

    /// You are running the SDK on the iOS simulator, which currently does not
    /// support CoreMotion services. You can test the SDK on real iOS devices
    /// only.
    case runningOnSimulatorUnsupported
  }

  /// Runtime errors that block the SDK initialization until the app is restarted
  /// or forever for the current device.
  public enum ProductionError: Error {
    /// The device doesn't have GPS capabilities, or it is malfunctioning.
    case locationServicesUnavalible

    /// The device doesn't have Motion capabilities, or it is malfunctioning.
    case motionActivityServicesUnavalible

    /// Motion activity permissions denied before SDK initialization. Granting
    /// them will restart the app, so in effect, they are denied during this app's
    /// session.
    case motionActivityPermissionsDenied
  }

  /// An error encountered during location tracking, after which the SDK can
  /// restore tracking location during this app's session.
  public enum RestorableError: Error {
    /// The user denied location permissions.
    case locationPermissionsDenied

    /// The user disabled location services systemwide.
    case locationServicesDisabled

    /// The user disabled motion services systemwide.
    case motionActivityServicesDisabled

    /// There was no network connection for 12 hours.
    ///
    /// SDK stops collecting location data after 12 hours without a network
    /// connection. It automatically resumes tracking after the connection is
    /// restored.
    case networkConnectionUnavailable

    /// HyperTrack's trial period has ended.
    case trialEnded

    /// There was an error processing your payment.
    case paymentDefault
  }

  /// An error encountered during location tracking, after which the SDK can't
  /// restore tracking location during this app's session.
  public enum UnrestorableError: Error {
    /// Publishable Key wan't found in HyperTrack's database.
    ///
    /// This error shouldn't happen in production, but due to its asynchronous
    /// nature, it can be detected only during tracking. SDK stops all functions
    /// until the app is recompiled with the correct Publishable Key.
    case invalidPublishableKey

    /// Motion activity permissions denied after SDK's initialization. Granting
    /// them will restart the app, so in effect, they are denied during this app's
    /// session.
    case motionActivityPermissionsDenied
  }

  /// A grouping of errors that can be emitted during tracking.
  ///
  /// Use this type with a `hyperTrackTrackingError()` function if you are
  /// subscribed to both restorable and unrestorable error notifications for the
  /// same selector.
  public enum TrackingError {
    case restorableError(RestorableError)
    case unrestorableError(UnrestorableError)

    /// A convenience property to retrieve `RestorableError` associated enum.
    public var restorableError: RestorableError? {
      guard case let .restorableError(value) = self else { return nil }
      return value
    }

    /// A convenience property to retrieve `UnrestorableError` associated enum.
    public var unrestorableError: UnrestorableError? {
      guard case let .unrestorableError(value) = self else { return nil }
      return value
    }
  }
}

extension Notification {
  /// A convenience function that recovers the `TrackingError` from a
  /// Notification. Use this function if you are subscribed to both
  /// notifications (`RestorableError` and `UnrestorableError`) in the same
  /// selector.
  public func hyperTrackTrackingError() -> HyperTrack.TrackingError? {
    if let error = self.userInfo?[Constant.Notification.Payload.errorKey]
      as? HyperTrack.RestorableError {
      return .restorableError(error)
    } else if let error = self.userInfo?[Constant.Notification.Payload.errorKey]
      as? HyperTrack.UnrestorableError
    { return .unrestorableError(error) } else { return nil }
  }

  /// A convenience function that recovers the `RestorableError` from a
  /// Notification.
  public func hyperTrackRestorableError() -> HyperTrack.RestorableError? {
    if let error = self.userInfo?[Constant.Notification.Payload.errorKey]
      as? HyperTrack.RestorableError
    { return error } else { return nil }
  }

  /// A convenience function that recovers the `UnrestorableError` from a
  /// Notification.
  public func hyperTrackUnrestorableError() -> HyperTrack.UnrestorableError? {
    if let error = self.userInfo?[Constant.Notification.Payload.errorKey]
      as? HyperTrack.UnrestorableError
    { return error } else { return nil }
  }
}
