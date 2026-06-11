import Foundation

extension LauncherStore {
    func loadCompanionData() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            let client = try requireClient()
            async let records: [WishRecord] = client.get(
                "/v1/wishes",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            async let statistics: [WishStatistics] = client.get(
                "/v1/wishes/statistics",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            async let note: DailyNote? = client.get(
                "/v1/notes",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            (wishes, wishStatistics, dailyNote) = try await (records, statistics, note)
        }
    }

    func syncWishes() async {
        await perform {
            let client = try requireClient()
            let body = CredentialRequest(credential: try requireCredential())
            let _: CountResponse = try await client.post("/v1/wishes/sync", body: body)
            await loadCompanionData()
        }
    }

    func refreshNote() async {
        await perform {
            let client = try requireClient()
            let body = CredentialRequest(credential: try requireCredential())
            dailyNote = try await client.post("/v1/notes/refresh", body: body)
        }
    }

    func importUIGF(from url: URL) async {
        await perform {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let client = try requireClient()
            let _: CountResponse = try await client.upload("/v1/wishes/import", json: data)
            await loadCompanionData()
        }
    }

    func exportUIGF(to url: URL) async {
        guard let uid = selectedRole?.uid else {
            message = LauncherError.roleMissing.localizedDescription
            return
        }
        await perform {
            let client = try requireClient()
            let data = try await client.download(
                "/v1/wishes/export",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            try data.write(to: url, options: .atomic)
        }
    }
}

