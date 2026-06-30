import Foundation

enum LongPollQuery {
    static func items(after revision: Int?) -> [URLQueryItem] {
        [
            URLQueryItem(name: "after_revision", value: String(revision ?? 0)),
            URLQueryItem(name: "wait_ms", value: "2000")
        ]
    }
}
