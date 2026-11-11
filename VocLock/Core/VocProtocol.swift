import Foundation
import CommonCrypto

/// VOC 门锁 BLE 协议（与 Tianmao Campus 5.0.0 逐字节对齐）
enum VocProtocol {

    static let serviceUUID = "00002760-08c2-11e1-9073-0e8ac72e1001"
    static let deviceNameKeyword = "vTmall"
    static let defaultAesKeyHex = "564F435F426C65536D6172744C6F636B"
    static let unlockSuccessAck = "55AAFF0B0001000A"
    static let fixedRequestRandom = "55AAFF0D00000B"
    static let fixedEstablishLink = "55AAFF13000011"

    // MARK: - hex

    static func hexString(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes { out += String(format: "%02X", b) }
        return out
    }

    static func bytes(_ hex: String) -> [UInt8] {
        var clean = hex.uppercased().filter { $0.isHexDigit }
        if clean.count % 2 != 0 { clean = "0" + clean }
        var out: [UInt8] = []
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            if let v = UInt8(clean[idx..<next], radix: 16) { out.append(v) }
            idx = next
        }
        return out
    }

    // MARK: - 校验 / 组帧

    static func checksum(_ hexStr: String) -> String {
        var total: UInt32 = 0
        for b in bytes(hexStr) { total = (total &+ UInt32(b)) % 256 }
        return String(format: "%02x", total)
    }

    static func xorHex(_ contentHex: String, _ keyHex: String) -> String {
        let keyChars = Array(keyHex.suffix(32))
        guard keyChars.count == 32 else { return "" }
        let content = bytes(contentHex)
        var out = ""
        out.reserveCapacity(content.count * 2)
        for (i, b) in content.enumerated() {
            let start = (i % 16) * 2
            let pair = String(keyChars[start]) + String(keyChars[start + 1])
            let k = UInt8(pair, radix: 16) ?? 0
            out += String(format: "%02x", b ^ k)
        }
        return out
    }

    /// FF | sign | len(2B) | content | cksum，补 0 到 16 字节整数倍
    static func assembleContent(sign: String, contentHex: String) -> String {
        let len = contentHex.count / 2
        var core = "FF" + sign + String(format: "%04x", len) + contentHex
        core += checksum("55AA" + core)
        let mod = core.count % 32
        let pad = (32 - mod) % 32
        return core + String(repeating: "0", count: pad)
    }

    static func aesKeyBytes(_ hex: String) -> [UInt8]? {
        let b = bytes(String(hex.suffix(32)))
        return b.count == 16 ? b : nil
    }

    static func randomNumber(from frameHex: String) -> String? {
        let f = frameHex.uppercased()
        guard f.count >= 46 else { return nil }
        let start = f.index(f.startIndex, offsetBy: 14)
        let end = f.index(start, offsetBy: 32)
        let rnd = String(f[start..<end])
        guard rnd.count == 32, rnd.allSatisfy({ $0.isHexDigit }) else { return nil }
        return rnd
    }

    // MARK: - AES-128 / ECB / NoPadding

    static func aesECB(_ input: [UInt8], key: [UInt8], encrypt: Bool) -> [UInt8]? {
        guard input.count % 16 == 0, !input.isEmpty, key.count == 16 else { return nil }
        var out = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(
            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            input, input.count,
            &out, out.count,
            &moved
        )
        guard status == kCCSuccess else { return nil }
        return Array(out.prefix(moved))
    }

    static func buildFrame(sign: String, contentHex: String,
                           randomFrameHex: String, aesKeyHex: String) -> String? {
        guard let rnd = randomNumber(from: randomFrameHex) else { return nil }
        let actualKeyHex = xorHex(rnd, aesKeyHex)
        guard let key = aesKeyBytes(actualKeyHex) else { return nil }
        let blob = bytes(assembleContent(sign: sign, contentHex: contentHex))
        guard let cipher = aesECB(blob, key: key, encrypt: true) else { return nil }
        let head = "55AA" + String(format: "%04x", cipher.count) + hexString(cipher)
        return (head + checksum(head)).uppercased()
    }

    static func unlockFrame(randomFrameHex: String, keyHex: String) -> String? {
        buildFrame(sign: "0B", contentHex: "", randomFrameHex: randomFrameHex, aesKeyHex: keyHex)
    }

    static func batteryFrame(randomFrameHex: String, keyHex: String) -> String? {
        buildFrame(sign: "01", contentHex: "", randomFrameHex: randomFrameHex, aesKeyHex: keyHex)
    }

    // MARK: - 收帧

    static func expectedFrameLength(_ buf: [UInt8]) -> Int? {
        guard buf.count >= 4, buf[0] == 0x55, buf[1] == 0xAA else { return nil }
        if buf[2] == 0xFF {
            guard buf.count >= 6 else { return nil }
            let n = (Int(buf[4]) << 8) | Int(buf[5])
            return 7 + n
        }
        let n = (Int(buf[2]) << 8) | Int(buf[3])
        guard n > 0, n <= 512 else { return nil }
        return 5 + n
    }

    // MARK: - 应答解密 / 身份校验

    static func cipherBytes(_ frameHex: String) -> [UInt8]? {
        let b = bytes(frameHex)
        guard b.count >= 5, b[0] == 0x55, b[1] == 0xAA else { return nil }
        let n = (Int(b[2]) << 8) | Int(b[3])
        guard n > 0, n % 16 == 0, b.count >= 5 + n else { return nil }
        return Array(b[4..<(4 + n)])
    }

    /// 解门锁应答。返回 (是否成功, 说明)。
    /// 明文形如 FF 13 0001 00 12 … ，第 5 字节是状态码，"00" 为成功。
    static func parseAck(frameHex: String, randomFrameHex: String, keyHex: String) -> (Bool, String) {
        guard let rnd = randomNumber(from: randomFrameHex) else { return (false, "随机数无效") }
        let actual = xorHex(rnd, keyHex)
        guard let key = aesKeyBytes(actual) else { return (false, "密钥无效") }
        guard let cipher = cipherBytes(frameHex),
              let plain = aesECB(cipher, key: key, encrypt: false) else {
            return (false, "应答无法解密")
        }
        let hex = hexString(plain).lowercased()
        guard hex.hasPrefix("ff") else { return (false, "密钥不匹配") }
        guard hex.count >= 10 else { return (false, "应答过短") }
        let start = hex.index(hex.startIndex, offsetBy: 8)
        let end = hex.index(start, offsetBy: 2)
        let status = String(hex[start..<end])
        return status == "00" ? (true, "ok") : (false, "状态码 \(status)")
    }
}
