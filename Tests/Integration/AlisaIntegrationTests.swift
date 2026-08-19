import Testing
@testable import AlisaCore
@testable import AlisaUI

@Test func testDatabaseSetup() async throws {
    try await DatabaseManager.shared.setup()
}

@Test func testFileSystem() async throws {
    let fs = FileSystemService.shared
    let (url, path) = try await fs.createProjectDirectory(name: "test", template: .empty)
    #expect(path.hasPrefix("test-"))
}

@Test func testKeychain() async throws {
    let keychain = KeychainService.shared
    try await keychain.deleteAllAPIKeys()
}