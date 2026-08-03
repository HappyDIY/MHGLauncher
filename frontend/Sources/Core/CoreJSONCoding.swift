import Foundation

extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: value) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: value) { return date }
            let local = DateFormatter()
            local.calendar = Calendar(identifier: .gregorian)
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let date = local.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无效日期")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
