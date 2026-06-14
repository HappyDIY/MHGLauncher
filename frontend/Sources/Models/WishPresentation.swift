import SwiftUI

extension WishRecord {
    var normalizedGachaType: String {
        gachaType == "400" ? "301" : gachaType
    }
}

extension WishBannerDetail {
    var poolName: String {
        switch gachaType {
        case "100": "新手祈愿"
        case "200": "常驻祈愿"
        case "301": "角色活动祈愿"
        case "302": "武器活动祈愿"
        default: "卡池 \(gachaType)"
        }
    }

    var poolIcon: String {
        switch gachaType {
        case "301": "person.2.fill"
        case "302": "shield.lefthalf.filled"
        case "200": "star.circle.fill"
        default: "sparkles"
        }
    }

    var poolAccent: Color {
        switch gachaType {
        case "301": .cyan
        case "302": .orange
        case "200": .purple
        default: .blue
        }
    }
}
