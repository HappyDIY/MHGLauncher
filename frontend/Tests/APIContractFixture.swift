import Foundation
@testable import MHGLauncher

struct APIContractCorpus: Decodable {
    struct Fixture: Decodable {
        let name: String
        let schema: String?
        let model: String?
        let body: JSONValue
    }

    let version: Int
    let endpoints: [[String]]
    let requests: [Fixture]
    let responses: [Fixture]

    static func load() throws -> Self {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "contracts/local-api/v1/corpus.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func request(named name: String) throws -> Fixture {
        try fixture(named: name, in: requests)
    }

    func response(named name: String) throws -> Fixture {
        try fixture(named: name, in: responses)
    }

    private func fixture(named name: String, in fixtures: [Fixture]) throws -> Fixture {
        guard let fixture = fixtures.first(where: { $0.name == name }) else {
            throw ContractFixtureError.missing(name)
        }
        return fixture
    }
}

enum ContractFixtureError: Error {
    case missing(String)
}

func contractData(_ fixture: APIContractCorpus.Fixture) throws -> Data {
    try JSONEncoder().encode(fixture.body)
}

func contractJSONObject<T: Encodable>(_ value: T) throws -> NSDictionary {
    let data = try JSONEncoder.api.encode(value)
    return try jsonObject(data)
}

func contractJSONObject(_ fixture: APIContractCorpus.Fixture) throws -> NSDictionary {
    try jsonObject(contractData(fixture))
}

private func jsonObject(_ data: Data) throws -> NSDictionary {
    guard let object = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
        throw ContractFixtureError.missing("JSON object")
    }
    return object
}
