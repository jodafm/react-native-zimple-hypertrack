import Compression
import Foundation
import UIKit

extension UIDevice {
  static let fullModelName: String = {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else {
        return identifier
      }
      return mapToDevice(
        identifier: identifier + String(UnicodeScalar(UInt8(value)))
      )
    }

    func mapToDevice(identifier: String) -> String {
      switch identifier {
        case "iPod5,1": return "iPod Touch 5"
        case "iPod7,1": return "iPod Touch 6"
        case "iPhone3,1", "iPhone3,2", "iPhone3,3": return "iPhone 4"
        case "iPhone4,1": return "iPhone 4s"
        case "iPhone5,1", "iPhone5,2": return "iPhone 5"
        case "iPhone5,3", "iPhone5,4": return "iPhone 5c"
        case "iPhone6,1", "iPhone6,2": return "iPhone 5s"
        case "iPhone7,2": return "iPhone 6"
        case "iPhone7,1": return "iPhone 6 Plus"
        case "iPhone8,1": return "iPhone 6s"
        case "iPhone8,2": return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3": return "iPhone 7"
        case "iPhone9,2", "iPhone9,4": return "iPhone 7 Plus"
        case "iPhone8,4": return "iPhone SE"
        case "iPhone10,1", "iPhone10,4": return "iPhone 8"
        case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4": return "iPad 2"
        case "iPad3,1", "iPad3,2", "iPad3,3": return "iPad 3"
        case "iPad3,4", "iPad3,5", "iPad3,6": return "iPad 4"
        case "iPad4,1", "iPad4,2", "iPad4,3": return "iPad Air"
        case "iPad5,3", "iPad5,4": return "iPad Air 2"
        case "iPad6,11", "iPad6,12": return "iPad 5"
        case "iPad7,5", "iPad7,6": return "iPad 6"
        case "iPad2,5", "iPad2,6", "iPad2,7": return "iPad Mini"
        case "iPad4,4", "iPad4,5", "iPad4,6": return "iPad Mini 2"
        case "iPad4,7", "iPad4,8", "iPad4,9": return "iPad Mini 3"
        case "iPad5,1", "iPad5,2": return "iPad Mini 4"
        case "iPad6,3", "iPad6,4": return "iPad Pro (9.7-inch)"
        case "iPad6,7", "iPad6,8": return "iPad Pro (12.9-inch)"
        case "iPad7,1", "iPad7,2": return "iPad Pro (12.9-inch) (2nd generation)"
        case "iPad7,3", "iPad7,4": return "iPad Pro (10.5-inch)"
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4":
          return "iPad Pro (11-inch)"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8":
          return "iPad Pro (12.9-inch) (3rd generation)"
        case "i386", "x86_64":
          return
            "Simulator \(mapToDevice(identifier: ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"))"
        default: return identifier
      }
    }
    return mapToDevice(identifier: identifier)
  }()
}

extension DateFormatter {
  static let iso8601Full: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()
}

extension Double {
    /// Rounds the double to decimal places value
    func rounded(_ places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension JSONDecoder {
  static var hyperTrackDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
    return decoder
  }
}

extension JSONEncoder {
  static var hyperTrackEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
    return encoder
  }
}

extension Data {
  func crc32() -> Crc32 {
    var res = Crc32()
    res.advance(withChunk: self)
    return res
  }

  func gzip() -> Data? {
    var header = Data([0x1F, 0x8B, 0x08, 0x00])
    // magic, magic, deflate, noflags
    var unixtime = UInt32(Date().timeIntervalSince1970).littleEndian
    header.append(Data(bytes: &unixtime, count: MemoryLayout<UInt32>.size))
    header.append(contentsOf: [0x00, 0x03])
    // normal compression level, unix file type
    let deflated = withUnsafeBytes {
      (sourcePtr: UnsafePointer<UInt8>) -> Data? in
      perform(
        COMPRESSION_STREAM_ENCODE,
        algorithm: COMPRESSION_ZLIB,
        source: sourcePtr,
        sourceSize: count,
        preload: header
      )
    }

    guard var result = deflated else { return nil }

    // append checksum
    var crc32: UInt32 = self.crc32().checksum.littleEndian
    result.append(Data(bytes: &crc32, count: MemoryLayout<UInt32>.size))

    // append size of original data
    var isize: UInt32 = UInt32(truncatingIfNeeded: count).littleEndian
    result.append(Data(bytes: &isize, count: MemoryLayout<UInt32>.size))

    return result
  }
}

private func perform(
  _ operation: compression_stream_operation,
  algorithm: compression_algorithm,
  source: UnsafePointer<UInt8>,
  sourceSize: Int,
  preload: Data = Data()
) -> Data? {
  let streamBase = UnsafeMutablePointer<compression_stream>.allocate(
    capacity: 1
  )
  defer { streamBase.deallocate() }
  var stream = streamBase.pointee

  let status = compression_stream_init(&stream, operation, algorithm)
  guard status != COMPRESSION_STATUS_ERROR else { return nil }
  defer { compression_stream_destroy(&stream) }

  let bufferSize = Swift.max(Swift.min(sourceSize, 64 * 1024), 64)
  let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
  defer { buffer.deallocate() }

  stream.dst_ptr = buffer
  stream.dst_size = bufferSize
  stream.src_ptr = source
  stream.src_size = sourceSize

  var res = preload
  let flags: Int32 = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

  while true {
    switch compression_stream_process(&stream, flags) {
      case COMPRESSION_STATUS_OK:
        guard stream.dst_size == 0 else { return nil }
        res.append(buffer, count: stream.dst_ptr - buffer)
        stream.dst_ptr = buffer
        stream.dst_size = bufferSize
      case COMPRESSION_STATUS_END:
        res.append(buffer, count: stream.dst_ptr - buffer)
        return res
      default: return nil
    }
  }
}

struct Crc32: CustomStringConvertible {
  private static let zLibCrc32: ZLibCrc32FuncPtr? = loadCrc32fromZLib()

  init() {}

  // C convention function pointer type matching the signature of `libz::crc32`
  private typealias ZLibCrc32FuncPtr = @convention(c) (
    _ cks: UInt32, _ buf: UnsafePointer<UInt8>, _ len: UInt32
  ) -> UInt32

  /// Raw checksum. Updated after a every call to `advance(withChunk:)`
  var checksum: UInt32 = 0

  /// Advance the current checksum with a chunk of data. Designed t be called multiple times.
  /// - parameter chunk: data to advance the checksum
  mutating func advance(withChunk chunk: Data) {
    if let fastCrc32 = Crc32.zLibCrc32 {
      checksum = chunk.withUnsafeBytes {
        (ptr: UnsafePointer<UInt8>) -> UInt32 in
        fastCrc32(checksum, ptr, UInt32(chunk.count))
      }
    } else { checksum = slowCrc32(start: checksum, data: chunk) }
  }

  /// Formatted checksum.
  var description: String { return String(format: "%08x", checksum) }

  /// Load `crc32()` from '/usr/lib/libz.dylib' if libz is installed.
  /// - returns: A function pointer to crc32() of zlib or nil if zlib can't be found
  private static func loadCrc32fromZLib() -> ZLibCrc32FuncPtr? {
    guard let libz = dlopen("/usr/lib/libz.dylib", RTLD_NOW) else { return nil }
    guard let fptr = dlsym(libz, "crc32") else { return nil }
    return unsafeBitCast(fptr, to: ZLibCrc32FuncPtr.self)
  }

  /// Rudimentary fallback implementation of the crc32 checksum. This is only a backup used
  /// when zlib can't be found under '/usr/lib/libz.dylib'.
  /// - returns: crc32 checksum (4 byte)
  private func slowCrc32(start: UInt32, data: Data) -> UInt32 {
    return ~data.reduce(~start) { (crc: UInt32, next: UInt8) -> UInt32 in
      let tableOffset = (crc ^ UInt32(next)) & 0xFF
      return lookUpTable[Int(tableOffset)] ^ crc >> 8
    }
  }

  /// Lookup table for faster crc32 calculation.
  /// table source: http://web.mit.edu/freebsd/head/sys/libkern/crc32.c
  private let lookUpTable: [UInt32] = [
    0x0000_0000, 0x7707_3096, 0xEE0E_612C, 0x9909_51BA, 0x076D_C419,
    0x706A_F48F, 0xE963_A535, 0x9E64_95A3, 0x0EDB_8832, 0x79DC_B8A4,
    0xE0D5_E91E, 0x97D2_D988, 0x09B6_4C2B, 0x7EB1_7CBD, 0xE7B8_2D07,
    0x90BF_1D91, 0x1DB7_1064, 0x6AB0_20F2, 0xF3B9_7148, 0x84BE_41DE,
    0x1ADA_D47D, 0x6DDD_E4EB, 0xF4D4_B551, 0x83D3_85C7, 0x136C_9856,
    0x646B_A8C0, 0xFD62_F97A, 0x8A65_C9EC, 0x1401_5C4F, 0x6306_6CD9,
    0xFA0F_3D63, 0x8D08_0DF5, 0x3B6E_20C8, 0x4C69_105E, 0xD560_41E4,
    0xA267_7172, 0x3C03_E4D1, 0x4B04_D447, 0xD20D_85FD, 0xA50A_B56B,
    0x35B5_A8FA, 0x42B2_986C, 0xDBBB_C9D6, 0xACBC_F940, 0x32D8_6CE3,
    0x45DF_5C75, 0xDCD6_0DCF, 0xABD1_3D59, 0x26D9_30AC, 0x51DE_003A,
    0xC8D7_5180, 0xBFD0_6116, 0x21B4_F4B5, 0x56B3_C423, 0xCFBA_9599,
    0xB8BD_A50F, 0x2802_B89E, 0x5F05_8808, 0xC60C_D9B2, 0xB10B_E924,
    0x2F6F_7C87, 0x5868_4C11, 0xC161_1DAB, 0xB666_2D3D, 0x76DC_4190,
    0x01DB_7106, 0x98D2_20BC, 0xEFD5_102A, 0x71B1_8589, 0x06B6_B51F,
    0x9FBF_E4A5, 0xE8B8_D433, 0x7807_C9A2, 0x0F00_F934, 0x9609_A88E,
    0xE10E_9818, 0x7F6A_0DBB, 0x086D_3D2D, 0x9164_6C97, 0xE663_5C01,
    0x6B6B_51F4, 0x1C6C_6162, 0x8565_30D8, 0xF262_004E, 0x6C06_95ED,
    0x1B01_A57B, 0x8208_F4C1, 0xF50F_C457, 0x65B0_D9C6, 0x12B7_E950,
    0x8BBE_B8EA, 0xFCB9_887C, 0x62DD_1DDF, 0x15DA_2D49, 0x8CD3_7CF3,
    0xFBD4_4C65, 0x4DB2_6158, 0x3AB5_51CE, 0xA3BC_0074, 0xD4BB_30E2,
    0x4ADF_A541, 0x3DD8_95D7, 0xA4D1_C46D, 0xD3D6_F4FB, 0x4369_E96A,
    0x346E_D9FC, 0xAD67_8846, 0xDA60_B8D0, 0x4404_2D73, 0x3303_1DE5,
    0xAA0A_4C5F, 0xDD0D_7CC9, 0x5005_713C, 0x2702_41AA, 0xBE0B_1010,
    0xC90C_2086, 0x5768_B525, 0x206F_85B3, 0xB966_D409, 0xCE61_E49F,
    0x5EDE_F90E, 0x29D9_C998, 0xB0D0_9822, 0xC7D7_A8B4, 0x59B3_3D17,
    0x2EB4_0D81, 0xB7BD_5C3B, 0xC0BA_6CAD, 0xEDB8_8320, 0x9ABF_B3B6,
    0x03B6_E20C, 0x74B1_D29A, 0xEAD5_4739, 0x9DD2_77AF, 0x04DB_2615,
    0x73DC_1683, 0xE363_0B12, 0x9464_3B84, 0x0D6D_6A3E, 0x7A6A_5AA8,
    0xE40E_CF0B, 0x9309_FF9D, 0x0A00_AE27, 0x7D07_9EB1, 0xF00F_9344,
    0x8708_A3D2, 0x1E01_F268, 0x6906_C2FE, 0xF762_575D, 0x8065_67CB,
    0x196C_3671, 0x6E6B_06E7, 0xFED4_1B76, 0x89D3_2BE0, 0x10DA_7A5A,
    0x67DD_4ACC, 0xF9B9_DF6F, 0x8EBE_EFF9, 0x17B7_BE43, 0x60B0_8ED5,
    0xD6D6_A3E8, 0xA1D1_937E, 0x38D8_C2C4, 0x4FDF_F252, 0xD1BB_67F1,
    0xA6BC_5767, 0x3FB5_06DD, 0x48B2_364B, 0xD80D_2BDA, 0xAF0A_1B4C,
    0x3603_4AF6, 0x4104_7A60, 0xDF60_EFC3, 0xA867_DF55, 0x316E_8EEF,
    0x4669_BE79, 0xCB61_B38C, 0xBC66_831A, 0x256F_D2A0, 0x5268_E236,
    0xCC0C_7795, 0xBB0B_4703, 0x2202_16B9, 0x5505_262F, 0xC5BA_3BBE,
    0xB2BD_0B28, 0x2BB4_5A92, 0x5CB3_6A04, 0xC2D7_FFA7, 0xB5D0_CF31,
    0x2CD9_9E8B, 0x5BDE_AE1D, 0x9B64_C2B0, 0xEC63_F226, 0x756A_A39C,
    0x026D_930A, 0x9C09_06A9, 0xEB0E_363F, 0x7207_6785, 0x0500_5713,
    0x95BF_4A82, 0xE2B8_7A14, 0x7BB1_2BAE, 0x0CB6_1B38, 0x92D2_8E9B,
    0xE5D5_BE0D, 0x7CDC_EFB7, 0x0BDB_DF21, 0x86D3_D2D4, 0xF1D4_E242,
    0x68DD_B3F8, 0x1FDA_836E, 0x81BE_16CD, 0xF6B9_265B, 0x6FB0_77E1,
    0x18B7_4777, 0x8808_5AE6, 0xFF0F_6A70, 0x6606_3BCA, 0x1101_0B5C,
    0x8F65_9EFF, 0xF862_AE69, 0x616B_FFD3, 0x166C_CF45, 0xA00A_E278,
    0xD70D_D2EE, 0x4E04_8354, 0x3903_B3C2, 0xA767_2661, 0xD060_16F7,
    0x4969_474D, 0x3E6E_77DB, 0xAED1_6A4A, 0xD9D6_5ADC, 0x40DF_0B66,
    0x37D8_3BF0, 0xA9BC_AE53, 0xDEBB_9EC5, 0x47B2_CF7F, 0x30B5_FFE9,
    0xBDBD_F21C, 0xCABA_C28A, 0x53B3_9330, 0x24B4_A3A6, 0xBAD0_3605,
    0xCDD7_0693, 0x54DE_5729, 0x23D9_67BF, 0xB366_7A2E, 0xC461_4AB8,
    0x5D68_1B02, 0x2A6F_2B94, 0xB40B_BE37, 0xC30C_8EA1, 0x5A05_DF1B,
    0x2D02_EF8D
  ]
}

extension TimeInterval {
  func toMilliseconds() -> Int { return Int(self * 1000) }
}

extension Date {
  static func - (lhs: Date, rhs: Date) -> TimeInterval {
    return lhs.timeIntervalSinceReferenceDate
      - rhs.timeIntervalSinceReferenceDate
  }
}

extension Array where Element: Any {
  static func != (left: [Element], right: [Element]) -> Bool {
    return !(left == right)
  }

  static func == (left: [Element], right: [Element]) -> Bool {
    if left.count != right.count { return false }
    var right = right
    loop: for leftValue in left {
      for (rightIndex, rightValue) in right.enumerated()
        where isEqual(leftValue, rightValue) {
        right.remove(at: rightIndex)
        continue loop
      }
      return false
    }
    return true
  }
}

extension Dictionary where Value: Any {
  static func != (left: [Key: Value], right: [Key: Value]) -> Bool {
    return !(left == right)
  }

  static func == (left: [Key: Value], right: [Key: Value]) -> Bool {
    if left.count != right.count { return false }
    for element in left {
      guard let rightValue = right[element.key],
        isEqual(rightValue, element.value)
        else { return false }
    }
    return true
  }
}

func isEqual(_ left: Any, _ right: Any) -> Bool {
  if type(of: left) == type(of: right),
    String(describing: left) == String(describing: right)
  { return true }
  if let left = left as? [Any], let right = right as? [Any] {
    return left == right
  }
  if let left = left as? [AnyHashable: Any],
    let right = right as? [AnyHashable: Any]
  { return left == right }
  return false
}

struct AnyCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init?(stringValue: String) { self.stringValue = stringValue }

  init?(intValue: Int) {
    self.intValue = intValue
    stringValue = String(intValue)
  }
}

extension KeyedDecodingContainer {
  /// Decodes a value of the given type for the given key.
  ///
  /// - parameter type: The type of value to decode.
  /// - parameter key: The key that the decoded value is associated with.
  /// - returns: A value of the requested type, if present for the given key
  ///   and convertible to the requested type.
  /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
  ///   is not convertible to the requested type.
  /// - throws: `DecodingError.keyNotFound` if `self` does not have an entry
  ///   for the given key.
  /// - throws: `DecodingError.valueNotFound` if `self` has a null entry for
  ///   the given key.
  func decode(_ type: [Any].Type, forKey key: KeyedDecodingContainer<K>.Key)
    throws -> [Any] {
    var values = try nestedUnkeyedContainer(forKey: key)
    return try values.decode(type)
  }

  /// Decodes a value of the given type for the given key.
  ///
  /// - parameter type: The type of value to decode.
  /// - parameter key: The key that the decoded value is associated with.
  /// - returns: A value of the requested type, if present for the given key
  ///   and convertible to the requested type.
  /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
  ///   is not convertible to the requested type.
  /// - throws: `DecodingError.keyNotFound` if `self` does not have an entry
  ///   for the given key.
  /// - throws: `DecodingError.valueNotFound` if `self` has a null entry for
  ///   the given key.
  func decode(
    _ type: [String: Any].Type,
    forKey key: KeyedDecodingContainer<K>.Key
  ) throws -> [String: Any] {
    let values = try nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
    return try values.decode(type)
  }

  /// Decodes a value of the given type for the given key, if present.
  ///
  /// This method returns `nil` if the container does not have a value
  /// associated with `key`, or if the value is null. The difference between
  /// these states can be distinguished with a `contains(_:)` call.
  ///
  /// - parameter type: The type of value to decode.
  /// - parameter key: The key that the decoded value is associated with.
  /// - returns: A decoded value of the requested type, or `nil` if the
  ///   `Decoder` does not have an entry associated with the given key, or if
  ///   the value is a null value.
  /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
  ///   is not convertible to the requested type.
  func decodeIfPresent(
    _ type: [Any].Type,
    forKey key: KeyedDecodingContainer<K>.Key
  ) throws -> [Any]? {
    guard contains(key), try decodeNil(forKey: key) == false else { return nil }
    return try decode(type, forKey: key)
  }

  /// Decodes a value of the given type for the given key, if present.
  ///
  /// This method returns `nil` if the container does not have a value
  /// associated with `key`, or if the value is null. The difference between
  /// these states can be distinguished with a `contains(_:)` call.
  ///
  /// - parameter type: The type of value to decode.
  /// - parameter key: The key that the decoded value is associated with.
  /// - returns: A decoded value of the requested type, or `nil` if the
  ///   `Decoder` does not have an entry associated with the given key, or if
  ///   the value is a null value.
  /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
  ///   is not convertible to the requested type.
  func decodeIfPresent(
    _ type: [String: Any].Type,
    forKey key: KeyedDecodingContainer<K>.Key
  ) throws -> [String: Any]? {
    guard contains(key), try decodeNil(forKey: key) == false else { return nil }
    return try decode(type, forKey: key)
  }
}

extension KeyedDecodingContainer {
  fileprivate func decode(_: [String: Any].Type) throws -> [String: Any] {
    var dictionary: [String: Any] = [:]
    for key in allKeys {
      if try decodeNil(forKey: key) {
        dictionary[key.stringValue] = NSNull()
      } else if let bool = try? decode(Bool.self, forKey: key) {
        dictionary[key.stringValue] = bool
      } else if let string = try? decode(String.self, forKey: key) {
        dictionary[key.stringValue] = string
      } else if let int = try? decode(Int.self, forKey: key) {
        dictionary[key.stringValue] = int
      } else if let double = try? decode(Double.self, forKey: key) {
        dictionary[key.stringValue] = double
      } else if let dict = try? decode([String: Any].self, forKey: key) {
        dictionary[key.stringValue] = dict
      } else if let array = try? decode([Any].self, forKey: key) {
        dictionary[key.stringValue] = array
      }
    }
    return dictionary
  }
}

extension UnkeyedDecodingContainer {
  fileprivate mutating func decode(_: [Any].Type) throws -> [Any] {
    var elements: [Any] = []
    while !isAtEnd {
      if try decodeNil() {
        elements.append(NSNull())
      } else if let int = try? decode(Int.self) {
        elements.append(int)
      } else if let bool = try? decode(Bool.self) {
        elements.append(bool)
      } else if let double = try? decode(Double.self) {
        elements.append(double)
      } else if let string = try? decode(String.self) {
        elements.append(string)
      } else if let values = try? nestedContainer(keyedBy: AnyCodingKey.self),
        let element = try? values.decode([String: Any].self) {
        elements.append(element)
      } else if var values = try? nestedUnkeyedContainer(),
        let element = try? values.decode([Any].self)
      { elements.append(element) }
    }
    return elements
  }
}

extension KeyedEncodingContainer {
  /// Encodes the given value for the given key.
  ///
  /// - parameter value: The value to encode.
  /// - parameter key: The key to associate the value with.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  mutating func encode(
    _ value: [String: Any],
    forKey key: KeyedEncodingContainer<K>.Key
  ) throws {
    var container = nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
    try container.encode(value)
  }

  /// Encodes the given value for the given key.
  ///
  /// - parameter value: The value to encode.
  /// - parameter key: The key to associate the value with.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  mutating func encode(
    _ value: [Any],
    forKey key: KeyedEncodingContainer<K>.Key
  ) throws {
    var container = nestedUnkeyedContainer(forKey: key)
    try container.encode(value)
  }

  /// Encodes the given value for the given key if it is not `nil`.
  ///
  /// - parameter value: The value to encode.
  /// - parameter key: The key to associate the value with.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  mutating func encodeIfPresent(
    _ value: [String: Any]?,
    forKey key: KeyedEncodingContainer<K>.Key
  ) throws {
    if let value = value {
      var container = nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
      try container.encode(value)
    } else { try encodeNil(forKey: key) }
  }

  /// Encodes the given value for the given key if it is not `nil`.
  ///
  /// - parameter value: The value to encode.
  /// - parameter key: The key to associate the value with.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  mutating func encodeIfPresent(
    _ value: [Any]?,
    forKey key: KeyedEncodingContainer<K>.Key
  ) throws {
    if let value = value {
      var container = nestedUnkeyedContainer(forKey: key)
      try container.encode(value)
    } else { try encodeNil(forKey: key) }
  }
}

extension KeyedEncodingContainer where K == AnyCodingKey {
  fileprivate mutating func encode(_ value: [String: Any]) throws {
    for (k, v) in value {
      let key = AnyCodingKey(stringValue: k)!
      switch v {
        case is NSNull: try encodeNil(forKey: key)
        case let string as String: try encode(string, forKey: key)
        case let int as Int: try encode(int, forKey: key)
        case let bool as Bool: try encode(bool, forKey: key)
        case let double as Double: try encode(double, forKey: key)
        case let dict as [String: Any]: try encode(dict, forKey: key)
        case let array as [Any]: try encode(array, forKey: key)
        default:
          debugPrint("Unsuported type!", v)
          continue
      }
    }
  }
}

extension UnkeyedEncodingContainer {
  /// Encodes the given value.
  ///
  /// - parameter value: The value to encode.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  fileprivate mutating func encode(_ value: [Any]) throws {
    for v in value {
      switch v {
        case is NSNull: try encodeNil()
        case let string as String: try encode(string)
        case let int as Int: try encode(int)
        case let bool as Bool: try encode(bool)
        case let double as Double: try encode(double)
        case let dict as [String: Any]: try encode(dict)
        case let array as [Any]:
          var values = nestedUnkeyedContainer()
          try values.encode(array)
        default: debugPrint("Unsuported type!", v)
      }
    }
  }

  /// Encodes the given value.
  ///
  /// - parameter value: The value to encode.
  /// - throws: `EncodingError.invalidValue` if the given value is invalid in
  ///   the current context for this format.
  fileprivate mutating func encode(_ value: [String: Any]) throws {
    var container = nestedContainer(keyedBy: AnyCodingKey.self)
    try container.encode(value)
  }
}
