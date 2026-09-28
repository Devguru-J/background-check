import Testing
@testable import BackgroundCheckCore

@Suite struct ProjectNameResolverTests {
    private func resolver(existing: Set<String>) -> ProjectNameResolver {
        ProjectNameResolver(roots: ["/Users/me/Devguru"], home: "/Users/me", fileExists: { existing.contains($0) })
    }

    @Test func walksUpToNearestProjectMarker() {
        let r = resolver(existing: ["/Users/me/Devguru/sites/my-site/package.json"])
        #expect(r.resolve(cwds: ["/Users/me/Devguru/sites/my-site/src"])
                == ProjectInfo(name: "my-site", path: "/Users/me/Devguru/sites/my-site"))
    }

    @Test func prefersCwdInsideRoot() {
        let r = resolver(existing: ["/Users/me/Devguru/api/.git"])
        #expect(r.resolve(cwds: ["/", "/Users/me/elsewhere", "/Users/me/Devguru/api"])
                == ProjectInfo(name: "api", path: "/Users/me/Devguru/api"))
    }

    @Test func fallsBackToCwdFolderName() {
        let r = resolver(existing: [])
        #expect(r.resolve(cwds: ["/Users/me/Devguru/loose"]) == ProjectInfo(name: "loose", path: "/Users/me/Devguru/loose"))
        #expect(r.resolve(cwds: ["/tmp/x"]) == ProjectInfo(name: "x", path: "/tmp/x"))
    }

    @Test func doesNotWalkAboveHomeOutsideRoots() {
        let r = resolver(existing: ["/Users/package.json"])
        #expect(r.resolve(cwds: ["/Users/me/other"]) == ProjectInfo(name: "other", path: "/Users/me/other"))
    }

    @Test func unknownWhenNoCwd() {
        #expect(resolver(existing: []).resolve(cwds: ["/"]) == ProjectInfo(name: "(unknown)", path: nil))
        #expect(resolver(existing: []).resolve(cwds: []) == ProjectInfo(name: "(unknown)", path: nil))
    }
}
