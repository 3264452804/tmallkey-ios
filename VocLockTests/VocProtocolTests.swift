import XCTest
@testable import VocLock

final class VocProtocolTests: XCTestCase {

    // 演示用数据，与任何真实门锁无关
    private let key = "000102030405060708090a0b0c0d0e0f"
    private let randomFrame = "55AAFF0D00110000112233445566778899AABBCCDDEEFF14"

    func testAESStandardVector() {
        let ct = VocProtocol.aesECB(
            VocProtocol.bytes("00112233445566778899aabbccddeeff"),
            key: VocProtocol.bytes("000102030405060708090a0b0c0d0e0f"),
            encrypt: true
        )
        XCTAssertEqual(VocProtocol.hexString(ct ?? []).lowercased(),
                       "69c4e0d86a7b0430d8cdb78070b4c55a")
    }

    func testUnlockFrameGolden() {
        XCTAssertEqual(VocProtocol.unlockFrame(randomFrameHex: randomFrame, keyHex: key),
                       "55AA0010EB99D2CB9F8DCB9384C2066473171995A2")
    }

    func testBatteryFrameGolden() {
        XCTAssertEqual(VocProtocol.batteryFrame(randomFrameHex: randomFrame, keyHex: key),
                       "55AA0010ADC57A17E60E8ADCF3B5BB2C4506982503")
    }

    func testRandomNumberExtraction() {
        XCTAssertEqual(VocProtocol.randomNumber(from: randomFrame),
                       "00112233445566778899AABBCCDDEEFF")
    }

    func testFrameLength() {
        XCTAssertEqual(VocProtocol.expectedFrameLength(VocProtocol.bytes(randomFrame)), 24)
        XCTAssertEqual(VocProtocol.expectedFrameLength(VocProtocol.bytes("55AA0010ADC57A17E60E8ADCF3B5BB2C4506982503")), 21)
        XCTAssertEqual(VocProtocol.expectedFrameLength(VocProtocol.bytes("55AAFF0D00000B")), 7)
    }

    /// 用正确钥匙能解开门锁应答（13 建立链路 / 0B 开锁）
    func testParseAckAcceptsMatchingKey() {
        let ack13 = "55AA0010B11134F75A321357D0A1872B4291CB3CEF"
        let ack0B = "55AA00106B2C51957559EB6889AFB5417D2E7A4E4E"
        XCTAssertTrue(VocProtocol.parseAck(frameHex: ack13, randomFrameHex: randomFrame, keyHex: key).0)
        XCTAssertTrue(VocProtocol.parseAck(frameHex: ack0B, randomFrameHex: randomFrame, keyHex: key).0)
    }

    /// 钥匙不对时必须拒绝（防止连到别人的门锁）
    func testParseAckRejectsWrongKey() {
        let ack13 = "55AA0010B11134F75A321357D0A1872B4291CB3CEF"
        XCTAssertFalse(VocProtocol.parseAck(frameHex: ack13, randomFrameHex: randomFrame,
                                            keyHex: "ffffffffffffffffffffffffffffffff").0)
    }
}
