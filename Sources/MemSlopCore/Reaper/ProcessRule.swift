import Foundation

/// A user-editable matcher. Used both for "slop" (what may be cleaned up) and for the protected list.
public struct ProcessRule: Identifiable, Hashable, Sendable, Codable {
    public enum Field: String, CaseIterable, Sendable, Codable {
        /// Executable file name, exact and case-insensitive (`uvicorn`).
        case executable
        /// Fragment of the full command line (`next dev`).
        case command
        /// Fragment of the executable path (`ms-playwright`).
        case path
        /// Name of the app bundle the process lives in, exact (`Discord`).
        case app

        public var title: String {
            switch self {
            case .executable: "Executable is"
            case .command: "Command contains"
            case .path: "Path contains"
            case .app: "App is"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var field: Field
    public var pattern: String
    public var isEnabled: Bool
    /// Allows matching regular GUI apps (only for throwaway test browsers).
    public var matchesApps: Bool

    public init(id: UUID = UUID(), name: String, field: Field, pattern: String, isEnabled: Bool = true, matchesApps: Bool = false) {
        self.id = id
        self.name = name
        self.field = field
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.matchesApps = matchesApps
    }

    public var isValid: Bool {
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func matches(_ process: ProcessSample) -> Bool {
        guard isEnabled, isValid else { return false }
        let needle = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        switch field {
        case .executable:
            return process.name.lowercased() == needle
        case .command:
            return process.commandLine.lowercased().contains(needle)
        case .path:
            return process.executablePath.lowercased().contains(needle)
        case .app:
            guard let bundle = ProcessGrouper.outermostAppBundle(in: process.executablePath) else { return false }
            let file = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            return file == needle || AppNames.shared.name(forBundleAt: bundle).lowercased() == needle
        }
    }
}

public extension ProcessRule {
    /// Dev slop that AI agents typically leave behind.
    static let defaultSlop: [ProcessRule] = [
        // Node.js
        .init(name: "Next.js dev server", field: .command, pattern: "next dev"),
        .init(name: "Next.js server", field: .command, pattern: "next-server"),
        .init(name: "Next.js server", field: .command, pattern: "next/dist/server/lib/start-server"),
        .init(name: "Vite", field: .command, pattern: "vite/bin/vite.js"),
        .init(name: "Vite", field: .command, pattern: "node_modules/.bin/vite"),
        .init(name: "Webpack dev server", field: .command, pattern: "webpack serve"),
        .init(name: "Webpack dev server", field: .command, pattern: "webpack-dev-server"),
        .init(name: "Nodemon", field: .command, pattern: "nodemon"),
        .init(name: "tsx watch", field: .command, pattern: "tsx watch"),
        .init(name: "npm run dev", field: .command, pattern: "npm run dev"),
        .init(name: "pnpm dev", field: .command, pattern: "pnpm dev"),
        .init(name: "pnpm run dev", field: .command, pattern: "pnpm run dev"),
        .init(name: "yarn dev", field: .command, pattern: "yarn dev"),
        .init(name: "Bun dev", field: .command, pattern: "bun run dev"),
        .init(name: "Bun dev", field: .command, pattern: "bun dev"),
        .init(name: "Turborepo dev", field: .command, pattern: "turbo run dev"),
        .init(name: "esbuild service", field: .command, pattern: "esbuild --service"),
        .init(name: "Storybook", field: .command, pattern: "storybook dev"),
        .init(name: "Astro dev", field: .command, pattern: "astro dev"),
        .init(name: "Nuxt dev", field: .command, pattern: "nuxi dev"),
        // Python
        .init(name: "Uvicorn", field: .command, pattern: "uvicorn"),
        .init(name: "Gunicorn", field: .command, pattern: "gunicorn"),
        .init(name: "Hypercorn", field: .command, pattern: "hypercorn"),
        .init(name: "Flask dev server", field: .command, pattern: "flask run"),
        .init(name: "FastAPI CLI", field: .command, pattern: "fastapi dev"),
        .init(name: "FastAPI CLI", field: .command, pattern: "fastapi run"),
        .init(name: "Django runserver", field: .command, pattern: "manage.py runserver"),
        .init(name: "Streamlit", field: .command, pattern: "streamlit run"),
        .init(name: "Gradio", field: .command, pattern: "gradio"),
        .init(name: "Jupyter", field: .command, pattern: "jupyter-lab"),
        .init(name: "Jupyter", field: .command, pattern: "jupyter-notebook"),
        .init(name: "Jupyter kernel", field: .command, pattern: "ipykernel_launcher"),
        .init(name: "Python http.server", field: .command, pattern: "http.server"),
        .init(name: "uv run", field: .command, pattern: "uv run"),
        // Test browsers
        .init(name: "Chrome for Testing", field: .path, pattern: "Google Chrome for Testing.app", matchesApps: true),
        .init(name: "Playwright browser", field: .path, pattern: "ms-playwright", matchesApps: true),
        .init(name: "Puppeteer browser", field: .path, pattern: ".cache/puppeteer", matchesApps: true),
        .init(name: "Headless Chrome", field: .command, pattern: "--headless"),
        .init(name: "Remote-debugging browser", field: .command, pattern: "--remote-debugging-port"),
    ]

    /// Apps the reaper never touches, even if a rule matches.
    static let defaultProtected: [ProcessRule] = [
        "Discord", "ChatGPT", "Claude", "Codex", "Obsidian", "Mail", "Slack", "Notion", "Spotify", "Messages",
        "WhatsApp", "Telegram", "zoom.us", "Microsoft Teams", "Finder", "Safari", "Google Chrome", "Arc", "Firefox",
        "MemSlop",
    ].map { ProcessRule(name: $0, field: .app, pattern: $0) }
}
