import Testing
@testable import AlisaCore

@Test func testModels() {
    let config = APIConfig(name: "test", baseURL: "https://test.com", keychainKeyRef: "test", model: "test")
    #expect(config.name == "test")
    #expect(config.model == "test")
}

@Test func testKeychainRef() {
    let config = APIConfig(name: "test", baseURL: "https://test.com", keychainKeyRef: "test", model: "test")
    #expect(config.keychainKeyRef == "test")
}

@Test func testRole() {
    let role = Role(name: "Alisa", systemPrompt: "You are a coder", isBuiltIn: true)
    #expect(role.isBuiltIn == true)
    #expect(role.name == "Alisa")
}

@Test func testSession() {
    let session = Session(roleID: UUID())
    #expect(session.messageCount == 0)
    #expect(session.title == "新会话")
}

@Test func testProject() {
    let project = Project(name: "Test", rootPath: "/test")
    #expect(project.name == "Test")
    #expect(project.template == nil)
}