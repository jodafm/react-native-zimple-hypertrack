import Foundation

protocol AbstractFileStorage: AnyObject {
  func store<T: Encodable>(
    _ object: T,
    to directory: FileStorage.Directory,
    as fileName: String
  )
  func retrieve<T: Decodable>(
    _ fileName: String,
    from directory: FileStorage.Directory,
    as type: T.Type
  ) -> T?
  func retrieve<T: Decodable>(_ filePath: String, as type: T.Type) -> T?
  func remove(_ fileName: String, from directory: FileStorage.Directory)
  func clear(_ directory: FileStorage.Directory)
}

final class FileStorage: AbstractFileStorage {
  enum Directory {
    // Only documents and other data that is user-generated,
    // or that cannot otherwise be recreated by your application, should be stored in
    // the <Application_Home>/Documents directory and will be automatically backed up by iCloud.
    case documents

    // Data that can be downloaded again or regenerated should be stored in
    // the <Application_Home>/Library/Caches directory. Examples of files you should put in
    // the Caches directory include database cache files and downloadable content,
    // such as that used by magazine, newspaper, and map applications.
    case caches
  }

  /// Returns URL constructed from specified directory
  fileprivate func getURL(for directory: Directory) -> URL? {
    var searchPathDirectory: FileManager.SearchPathDirectory

    switch directory {
      case .documents: searchPathDirectory = .documentDirectory
      case .caches: searchPathDirectory = .cachesDirectory
    }

    if let url = FileManager.default.urls(
      for: searchPathDirectory,
      in: .userDomainMask
    ).first { return url } else {
      logFile.error("Failed to Get URL for directory: \(directory)")
      return nil
    }
  }

  /// Store an encodable struct to the specified directory on disk
  ///
  /// - Parameters:
  ///   - object: the encodable struct to store
  ///   - directory: where to store the struct
  ///   - fileName: what to name the file where the struct data will be stored
  func store<T: Encodable>(
    _ object: T,
    to directory: Directory,
    as fileName: String
  ) {
    guard
      let url = getURL(for: directory)?.appendingPathComponent(
        fileName,
        isDirectory: false
      )
      else {
        logFile.error(
          "Failed to store struct with object: \(object) to directory: \(directory) as fileName: \(fileName) with guard failure url: nil"
        )
        return
    }

    let encoder = JSONEncoder.hyperTrackEncoder
    do {
      let data = try encoder.encode(object)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      FileManager.default.createFile(
        atPath: url.path,
        contents: data,
        attributes: nil
      )
    } catch {
      logFile.error(
        "Failed to store struct with object: \(object) to directory: \(directory) as fileName: \(fileName) with error: \(error)"
      )
    }
  }

  /// Retrieve and convert a struct from a file on disk
  ///
  /// - Parameters:
  ///   - fileName: name of the file where struct data is stored
  ///   - directory: directory where struct data is stored
  ///   - type: struct type (i.e. Message.self)
  /// - Returns: decoded struct model(s) of data
  func retrieve<T: Decodable>(
    _ fileName: String,
    from directory: Directory,
    as type: T.Type
  ) -> T? {
    guard
      let url = getURL(for: directory)?.appendingPathComponent(
        fileName,
        isDirectory: false
      )
      else { return nil }

    if let data = FileManager.default.contents(atPath: url.path) {
      let decoder = JSONDecoder.hyperTrackDecoder
      do {
        let model = try decoder.decode(type, from: data)
        return model
      } catch {}
    }
    return nil
  }

  func retrieve<T>(_ filePath: String, as type: T.Type) -> T?
    where T: Decodable {
    guard let data = FileManager.default.contents(atPath: filePath) else {
      logFile.error(
        "Failed to retrieve and convert a struct with filePath: \(filePath) as type: \(type) with guard failure to retrieve contents of filePath: \(filePath)"
      )
      return nil
    }
    do {
      if filePath.contains("plist") {
        return try PropertyListDecoder().decode(type, from: data)
      } else { return try JSONDecoder().decode(type, from: data) }
    } catch {
      logFile.error(
        "Failed to retrieve and convert a struct with filePath: \(filePath) as type: \(type) with error: \(error)"
      )
    }
    return nil
  }

  /// Remove all files at specified directory
  func clear(_ directory: Directory) {
    guard let url = getURL(for: directory) else {
      logFile.error(
        "Failed to clear all files at directory: \(directory) with guard failure url: nil"
      )
      return
    }
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: []
      )
      for fileUrl in contents {
        try FileManager.default.removeItem(at: fileUrl)
      }
    } catch {
      logFile.error(
        "Failed to clear all files at directory: \(directory) with error: \(error)"
      )
    }
  }

  /// Remove specified file from specified directory
  func remove(_ fileName: String, from directory: Directory) {
    guard
      let url = getURL(for: directory)?.appendingPathComponent(
        fileName,
        isDirectory: false
      )
      else {
        logFile.error(
          "Failed to remove fileName: \(fileName) from directory: \(directory) with guard failure url: nil"
        )
        return
    }
    if FileManager.default.fileExists(atPath: url.path) {
      do { try FileManager.default.removeItem(at: url) } catch {
        logFile.error(
          "Failed to remove fileName: \(fileName) from directory: \(directory) with error: \(error)"
        )
      }
    }
  }

  /// Returns BOOL indicating whether file exists at specified directory with specified file name
  fileprivate func fileExists(_ fileName: String, in directory: Directory)
    -> Bool {
    guard
      let url = getURL(for: directory)?.appendingPathComponent(
        fileName,
        isDirectory: false
      )
      else {
        logFile.error(
          "Failed to check existence of fileName: \(fileName) in directory: \(directory) with guard failure url: nil"
        )
        return false
    }
    return FileManager.default.fileExists(atPath: url.path)
  }
}
