import Foundation

actor RuntimeInstallGate {
    private struct Flight {
        let id: UUID
        let task: Task<InstalledRuntime, Error>
    }

    private var flights: [RuntimeInstallScope: Flight] = [:]

    func run(
        scope: RuntimeInstallScope,
        operation: @escaping @Sendable () async throws -> InstalledRuntime
    ) async throws -> InstalledRuntime {
        if let flight = flights[scope] {
            return try await flight.task.value
        }
        let flight = Flight(id: UUID(), task: Task(operation: operation))
        flights[scope] = flight
        do {
            let result = try await flight.task.value
            clear(scope: scope, id: flight.id)
            return result
        } catch {
            clear(scope: scope, id: flight.id)
            throw error
        }
    }

    func cancel(scope: RuntimeInstallScope) {
        flights[scope]?.task.cancel()
    }

    private func clear(scope: RuntimeInstallScope, id: UUID) {
        guard flights[scope]?.id == id else { return }
        flights.removeValue(forKey: scope)
    }
}
