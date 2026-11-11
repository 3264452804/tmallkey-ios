import Foundation

enum AppConfig {
    /// 门锁 MAC 仅用于界面展示（iOS 不允许 App 读取真实 MAC，连接靠 CBPeripheral）
    static let doorMac = ""
    static let doorName = "宿舍门"
    static let roomLabel = "我的宿舍"
    /// 首次启动不预填钥匙，避免把钥匙写进仓库；在 App 里粘一次后存 Keychain
    static let defaultKey = ""
}
