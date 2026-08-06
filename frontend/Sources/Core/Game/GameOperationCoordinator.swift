import Foundation

enum GameOperationKind: Sendable {
    case resources
    case launch
}

actor GameOperationCoordinator {
    private struct ActiveOperation {
        let token: UUID
        let kind: GameOperationKind
    }

    private var active: ActiveOperation?

    func acquire(_ kind: GameOperationKind) throws -> UUID {
        guard let active else {
            let token = UUID()
            self.active = ActiveOperation(token: token, kind: kind)
            return token
        }
        let code: String
        switch kind {
        case .resources:
            code = "game_resource_busy"
        case .launch:
            code = "game_launch_busy"
        }
        let message = switch active.kind {
        case .resources: "游戏资源任务正在运行"
        case .launch: "游戏启动会话正在运行"
        }
        throw LauncherCoreError(code: code, message: message)
    }

    func release(_ token: UUID) {
        guard active?.token == token else { return }
        active = nil
    }
}
