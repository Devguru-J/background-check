import Foundation

public enum ToolNameResolver {
    /// 확장자를 뗀 파일 이름 → 표시 이름
    static let markers: [String: String] = [
        "astro": "astro", "vite": "vite", "next": "next", "nuxt": "nuxt", "nuxi": "nuxt",
        "remix": "remix", "wrangler": "wrangler", "webpack": "webpack", "webpack-dev-server": "webpack",
        "storybook": "storybook", "parcel": "parcel", "eleventy": "eleventy", "gatsby": "gatsby",
        "svelte-kit": "svelte-kit", "turbo": "turbo", "nodemon": "nodemon", "tsx": "tsx",
        "uvicorn": "uvicorn", "flask": "flask", "manage": "django", "http.server": "http.server",
        "rails": "rails", "hugo": "hugo",
    ]
    static let subcommands: Set<String> = ["dev", "preview", "serve", "server", "start", "runserver", "run", "watch"]
    static let scriptExtensions = [".js", ".mjs", ".cjs", ".ts", ".py"]

    /// commands: 세션 루트가 먼저 오는 멤버 명령어 목록
    public static func resolve(commands: [String], fallback: String) -> String {
        for command in commands {
            let tokens = command.split(separator: " ").map(String.init)
            for (i, token) in tokens.enumerated() {
                guard let name = markers[strip(token)] else { continue }
                if i + 1 < tokens.count, subcommands.contains(tokens[i + 1]) {
                    return "\(name) \(tokens[i + 1])"
                }
                return name
            }
        }
        return fallback
    }

    static func strip(_ token: String) -> String {
        var name = (token as NSString).lastPathComponent
        if let ext = scriptExtensions.first(where: { name.hasSuffix($0) }) { name.removeLast(ext.count) }
        return name
    }
}
