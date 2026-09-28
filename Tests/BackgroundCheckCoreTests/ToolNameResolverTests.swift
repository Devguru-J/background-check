import Testing
@testable import BackgroundCheckCore

@Suite struct ToolNameResolverTests {
    @Test(arguments: [
        ("node /Users/me/Devguru/site/node_modules/.bin/astro dev", "astro dev"),
        ("node /Users/me/site/node_modules/astro/astro.js preview", "astro preview"),
        ("node /Users/me/site/node_modules/vite/bin/vite.js", "vite"),
        ("node /Users/me/site/node_modules/.bin/next dev --turbo", "next dev"),
        ("python3 -m http.server 8000", "http.server"),
        ("python manage.py runserver", "django runserver"),
        ("/opt/homebrew/bin/hugo server -D", "hugo server"),
        ("node /Users/me/My Projects/site/node_modules/.bin/astro dev", "astro dev"),
    ])
    func resolvesKnownTools(command: String, expected: String) {
        #expect(ToolNameResolver.resolve(commands: [command], fallback: "node") == expected)
    }

    @Test func looksPastGenericRootCommand() {
        let commands = ["npm run dev", "sh -c astro dev", "node /x/node_modules/.bin/astro dev"]
        #expect(ToolNameResolver.resolve(commands: commands, fallback: "node") == "astro dev")
    }

    @Test func fallsBack() {
        #expect(ToolNameResolver.resolve(commands: ["node server.js"], fallback: "node") == "node")
    }
}
