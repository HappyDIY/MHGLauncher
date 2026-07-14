import Foundation

actor RuntimeInstallGate {
    private struct Flight {
        let id: UUID
        let task: Task<InstalledRuntime, Error>
        var waiters: Set<UUID>
    }

    private var flights: [RuntimeInstallScope: Flight] = [:]

    func run(
        scope: RuntimeInstallScope,
        operation: @escaping @Sendable () async throws -> InstalledRuntime
    ) async throws -> InstalledRuntime {
        let waiter = UUID()
        let flight: Flight
        if var current = flights[scope] {
            current.waiters.insert(waiter)
            flights[scope] = current
            flight = current
        } else {
            flight = Flight(id: UUID(), task: Task(operation: operation), waiters: [waiter])
            flights[scope] = flight
        }
        return try await withTaskCancellationHandler {
            do {
                let result = try await flight.task.value
                try Task.checkCancellation()
                clear(scope: scope, id: flight.id)
                return result
            } catch {
                clear(scope: scope, id: flight.id)
                throw error
            }
        } onCancel: {
            Task { await self.cancel(scope: scope, id: flight.id, waiter: waiter) }
        }
    }

    private func cancel(scope: RuntimeInstallScope, id: UUID, waiter: UUID) {
        guard var flight = flights[scope], flight.id == id else { return }
        flight.waiters.remove(waiter)
        flights[scope] = flight
        if flight.waiters.isEmpty { flight.task.cancel() }
    }

    private func clear(scope: RuntimeInstallScope, id: UUID) {
        guard flights[scope]?.id == id else { return }
        flights.removeValue(forKey: scope)
    }
}
