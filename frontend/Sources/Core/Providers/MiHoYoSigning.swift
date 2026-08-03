import CryptoKit
import Foundation
import Security

enum MiHoYoSigning {
    enum Kind { case prod, x4, lk2 }

    private static let salts: [Kind: String] = [
        .prod: "JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS",
        .x4: "xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs",
        .lk2: "sidQFEglajEz7FA0Aj7HQPV88zpf17SO"
    ]
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    static func sign(
        _ kind: Kind,
        body: String = "",
        query: String = "",
        generation: Int = 2,
        now: Date = Date(),
        random: Data? = nil
    ) -> String {
        let timestamp = Int(now.timeIntervalSince1970)
        let bytes = random ?? secureRandom(count: 6)
        let nonce: String
        if kind == .x4 {
            let first = UInt16(bytes.first ?? 0) << 8
            let second = UInt16(bytes.dropFirst().first ?? 0)
            nonce = String(100_000 + Int(first | second) % 100_000)
        } else {
            nonce = String(bytes.prefix(6).map { alphabet[Int($0) % alphabet.count] })
        }
        let normalized = normalizedQuery(query)
        var input = "salt=\(salts[kind]!)&t=\(timestamp)&r=\(nonce)"
        if generation == 2 {
            input += "&b=\(kind == .prod && body.isEmpty ? "{}" : body)&q=\(normalized)"
        }
        return "\(timestamp),\(nonce),\(CoreHash.md5(Data(input.utf8)))"
    }

    static func cookies(_ raw: String) -> [String: String] {
        raw.replacingOccurrences(of: " ", with: "").split(separator: ";").reduce(into: [:]) { result, item in
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[0].isEmpty, result[String(pair[0])] == nil else { return }
            result[String(pair[0])] = String(pair[1])
        }
    }

    static func serialize(_ values: [String: String]) -> String {
        values.keys.sorted().compactMap { key in
            values[key]?.nonempty.map { "\(key)=\($0)" }
        }.joined(separator: ";")
    }

    static func encryptPassport(_ value: String) throws -> String {
        let pem = """
        MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDvekdPMHN3AYhm/vktJT+YJr7
        cI5DcsNKqdsx5DZX0gDuWFuIjzdwButrIYPNmRJ1G8ybDIF7oDW2eEpm5sMbL9zs
        9ExXCdvqrn51qELbqj0XxtMTIpaCHFSI50PfPpTFV9Xt/hmyVwokoOXFlAEgCn+Q
        CgGs52bFoYMtyi+xEQIDAQAB
        """.replacingOccurrences(of: "\n", with: "")
        guard let keyData = Data(base64Encoded: pem),
              let key = SecKeyCreateWithData(keyData as CFData, [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits: 1024
              ] as CFDictionary, nil) else {
            throw LauncherCoreError(code: "passport_key_invalid", message: "登录加密密钥无效")
        }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key, .rsaEncryptionPKCS1, Data(value.utf8) as CFData, &error
        ) as Data? else {
            throw LauncherCoreError(code: "passport_encrypt_failed", message: "登录信息加密失败")
        }
        return encrypted.base64EncodedString()
    }

    static func secureRandom(count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess)
        return data
    }

    private static func normalizedQuery(_ query: String) -> String {
        guard var components = URLComponents(string: "https://localhost/?\(query)") else { return query }
        components.queryItems = (components.queryItems ?? []).sorted {
            if $0.name == $1.name { return ($0.value ?? "") < ($1.value ?? "") }
            return $0.name < $1.name
        }
        return components.percentEncodedQuery ?? ""
    }
}

actor MiHoYoDevice {
    struct Snapshot: Codable, Sendable {
        var profile: String
        var deviceID: String
        var fpDeviceID: String
        var hoyoplayDeviceID: String
        var deviceName: String
        var productName: String
        var deviceFP: String
    }

    private let url: URL
    private let transport: any HTTPTransport
    private var value: Snapshot

    init(dataDirectory: URL, transport: any HTTPTransport) throws {
        url = dataDirectory.appending(path: "device.json")
        self.transport = transport
        if GameFilesystem.regularFile(url),
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder.api.decode(Snapshot.self, from: data),
           saved.profile == "snap-hutao-android-v2" {
            value = saved
        } else {
            value = Snapshot(
                profile: "snap-hutao-android-v2",
                deviceID: UUID().uuidString,
                fpDeviceID: MiHoYoSigning.secureRandom(count: 8).map { String(format: "%02x", $0) }.joined(),
                hoyoplayDeviceID: Self.randomLowercase(count: 53),
                deviceName: Self.randomText(count: 12),
                productName: Self.randomText(count: 6),
                deviceFP: ""
            )
            try Self.save(value, to: url)
        }
    }

    func snapshot() -> Snapshot { value }

    func fingerprint() async throws -> Snapshot {
        if !value.deviceFP.isEmpty { return value }
        let body: [String: String] = [
            "device_id": value.fpDeviceID,
            "seed_id": UUID().uuidString,
            "seed_time": String(Int(Date().timeIntervalSince1970 * 1000)),
            "platform": "2",
            "device_fp": MiHoYoSigning.secureRandom(count: 7).map { String(format: "%02x", $0) }.joined().prefix(13).description,
            "app_name": "bbs_cn",
            "bbs_device_id": value.deviceID,
            "ext_fields": try Self.extFields(value)
        ]
        var request = URLRequest(url: URL(string: "https://public-data-api.mihoyo.com/device-fp/api/getFp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.api.encode(body)
        let payload = try await transport.send(
            request,
            policy: .mihoyo,
            maximumBytes: 1024 * 1024
        )
        let envelope = try MiHoYoEnvelope.decode(payload)
        guard let fp = envelope.data.objectValue?["device_fp"]?.text.nonempty else {
            throw LauncherCoreError(code: "device_fp_failed", message: "米游社设备注册失败，请稍后重试")
        }
        value.deviceFP = fp
        try Self.save(value, to: url)
        return value
    }

    private static func save(_ value: Snapshot, to url: URL) throws {
        try GameFilesystem.writePrivate(JSONEncoder.api.encode(value), to: url)
    }

    private static func randomLowercase(count: Int) -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String(MiHoYoSigning.secureRandom(count: count).map { alphabet[Int($0) % alphabet.count] })
    }

    private static func randomText(count: Int) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        return String(MiHoYoSigning.secureRandom(count: count).map { alphabet[Int($0) % alphabet.count] })
    }

    private static func extFields(_ value: Snapshot) throws -> String {
        let fields: [String: JSONValue] = [
            "proxyStatus": .number(0), "isRoot": .number(0), "romCapacity": .string("512"),
            "deviceName": .string(value.deviceName), "productName": .string(value.productName),
            "model": .string(value.deviceName), "brand": .string("XiaoMi"), "hardware": .string("qcom"),
            "deviceType": .string("OP5913L1"), "sdkVersion": .string("34"), "osVersion": .string("14"),
            "cpuType": .string("arm64-v8a"), "manufacturer": .string("XiaoMi"),
            "packageName": .string("com.mihoyo.hyperion"), "networkType": .string("WiFi")
        ]
        return String(decoding: try JSONEncoder.api.encode(fields), as: UTF8.self)
    }
}

extension HTTPSHostPolicy {
    static let mihoyo = HTTPSHostPolicy(
        exactHosts: ["passport-api.mihoyo.com", "api-takumi.mihoyo.com", "api-takumi-record.mihoyo.com", "public-data-api.mihoyo.com", "public-operation-hk4e.mihoyo.com"],
        suffixes: ["mihoyo.com"]
    )
}

struct MiHoYoEnvelope: Sendable {
    let retcode: Int
    let message: String
    let data: JSONValue

    static func decode(_ payload: HTTPPayload, allowRetcode: Set<Int> = []) throws -> Self {
        guard payload.data.count <= 64 * 1024 * 1024,
              let root = try? JSONDecoder.api.decode([String: JSONValue].self, from: payload.data) else {
            throw LauncherCoreError(code: "mihoyo_payload_invalid", message: "米游社响应格式无效")
        }
        let code = root["retcode"]?.int ?? 0
        let message = root["message"]?.text ?? ""
        guard (200..<300).contains(payload.statusCode), code == 0 || allowRetcode.contains(code) else {
            throw LauncherCoreError(
                code: "mihoyo_error",
                message: message.nonempty ?? "米游社请求失败（错误码 \(code)）",
                details: ["retcode": .string(String(code))]
            )
        }
        return Self(retcode: code, message: message, data: root["data"] ?? .object([:]))
    }
}

extension JSONValue {
    var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        default: ""
        }
    }
    var int: Int { integerValue ?? Int(text) ?? 0 }
    var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var arrayValue: [JSONValue] { if case .array(let value) = self { value } else { [] } }
}
