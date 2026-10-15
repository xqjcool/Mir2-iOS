import XCTest
@testable import MirNavigation
final class ChatChannelTests:XCTestCase {
    func testServerChannelMapping() {
        XCTAssertEqual(MirChatChannel.name(for:40),"当前")
        XCTAssertEqual(MirChatChannel.name(for:102),"当前")
        XCTAssertEqual(MirChatChannel.name(for:104),"行会")
        XCTAssertEqual(MirChatChannel.name(for:100),"系统")
        XCTAssertEqual(MirChatChannel.name(for:103),"私聊")
        XCTAssertEqual(MirChatChannel.name(for:101),"组队")
    }
}
