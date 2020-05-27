import Foundation

struct AuthToken: Codable {
  let token: String
  let expiresIn: Int

  init() {
    token = ""
    expiresIn = 0
  }

  enum Keys: String, CodingKey {
    case token = "access_token"
    case expiresIn = "expires_in"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Keys.self)
    token = (try? container.decode(String.self, forKey: .token)) ?? ""
    expiresIn = (try? container.decode(Int.self, forKey: .expiresIn)) ?? 0
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Keys.self)
    try container.encode(token, forKey: .token)
    try container.encode(expiresIn, forKey: .expiresIn)
  }
}
