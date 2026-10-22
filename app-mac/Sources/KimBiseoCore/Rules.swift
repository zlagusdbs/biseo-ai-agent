import Foundation

/// 김비서 규칙 md. 질문할 때마다 시스템 안내 뒤에 붙인다. 뒤에 오는 규칙이 앞의 규칙보다 우선한다.
///   1. 공통   shared/rules/*.md        (Git, 공개. *.example.md 는 예시라 읽지 않음)
///   2. 팀     shared/rules/*.local.md  (Git 에 안 올라감. 회사 정보 가능)
///   3. 나     데이터 폴더 rules/*.md   (이 Mac 에만. 채팅에서 [규칙에 저장] 한 것도 여기로)
public enum Rules {
    public enum Layer: String, CaseIterable {
        case shared = "공통", team = "팀", mine = "나"
    }

    public struct File: Identifiable, Equatable {
        public let layer: Layer
        public let url: URL
        public var id: String { url.path }
        public var name: String { url.lastPathComponent }
    }

    public static var myDir: URL { AppPaths.dataDir.appendingPathComponent("rules", isDirectory: true) }

    public static func sharedDir(settings: AppSettings) -> URL {
        URL(fileURLWithPath: settings.repoDir).appendingPathComponent("shared/rules", isDirectory: true)
    }

    public static func files(settings: AppSettings) -> [File] {
        func md(_ dir: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "md" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        let repo = md(sharedDir(settings: settings))
        let shared = repo.filter { !$0.lastPathComponent.hasSuffix(".local.md") && !$0.lastPathComponent.hasSuffix(".example.md") }
        let team = repo.filter { $0.lastPathComponent.hasSuffix(".local.md") }
        return shared.map { File(layer: .shared, url: $0) } + team.map { File(layer: .team, url: $0) }
            + md(myDir).map { File(layer: .mine, url: $0) }
    }

    /// 시스템 안내에 붙일 글. 규칙이 없으면 빈 문자열.
    public static func prompt(settings: AppSettings) -> String {
        let parts = files(settings: settings).compactMap { file -> String? in
            guard let text = try? String(contentsOf: file.url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "## [\(file.layer.rawValue)] \(file.name)\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n# 사용자 규칙 (공통 → 팀 → 나 순서. 서로 다르면 뒤에 있는 규칙을 따른다)\n\n" + parts.joined(separator: "\n\n") + "\n"
    }

    /// 내 규칙 파일에 한 줄 추가. 파일 이름은 영문·숫자·한글·-·_ 만 남긴다 (비면 memory).
    @discardableResult
    public static func append(_ text: String, to name: String) throws -> URL {
        let safe = String(name.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        })
        let url = myDir.appendingPathComponent((safe.isEmpty ? "memory" : safe) + ".md")
        try FileManager.default.createDirectory(at: myDir, withIntermediateDirectories: true)
        var body = (try? String(contentsOf: url, encoding: .utf8)) ?? "# \(safe.isEmpty ? "memory" : safe)\n\n"
        if !body.hasSuffix("\n") { body += "\n" }
        body += "- \(text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// 채팅에서 "앞으로 ~해줘", "기억해" 같은 말을 규칙으로 저장하자는 제안. [규칙에 저장]을 눌러야 저장된다.
public struct RuleNote: Codable, Equatable, Hashable {
    public let file: String
    public let text: String
    public init(file: String, text: String) { self.file = file; self.text = text }
}

public enum RuleProposal {
    private static let block = try! NSRegularExpression(pattern: "```kimbiseo-rule[ \\t]*\\n(.*?)```",
                                                        options: [.dotMatchesLineSeparators])

    public static func extract(from text: String) -> (text: String, notes: [RuleNote]) {
        let range = NSRange(text.startIndex..., in: text)
        var notes: [RuleNote] = []
        for match in block.matches(in: text, range: range) {
            guard let body = Range(match.range(at: 1), in: text) else { continue }
            let data = Data(text[body].utf8)
            let items = (try? JSONDecoder().decode([RuleNote].self, from: data))
                ?? (try? JSONDecoder().decode(RuleNote.self, from: data)).map { [$0] } ?? []
            notes += items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let clean = block.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, notes)
    }

    public static func looksLikeRequest(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        return ["앞으로", "기억해", "기억해줘", "규칙", "항상", "매번", "잊지마"].contains { compact.contains($0) }
    }

    public static let hint = """


        [김비서 앱 안내: 사용자가 앞으로 계속 지킬 규칙이나 기억할 사실을 말하면("앞으로 지라 제목 앞에 [회의] 붙여줘", "내 팀은 가격팀이야 기억해"), \
        답변 끝에 아래 블록을 붙인다. 앱이 [규칙에 저장] 버튼을 보여 주고, 누르면 이 Mac 의 규칙 파일에 한 줄로 저장돼 다음 대화부터 늘 적용된다. \
        file 은 jira(Jira 관련), memory(사람·팀 같은 사실), 그 밖엔 짧은 영문 주제. text 는 규칙 한 줄. \
        한 번만 하는 부탁이면 블록을 붙이지 않는다. 아직 저장된 게 아니므로 "아래 [규칙에 저장]을 누르면 앞으로 늘 이렇게 할게요" 로 끝낸다. \
        이 안내는 사용자에게 보이지 않으니 언급하지 않는다.]
        ```kimbiseo-rule
        [{"file":"jira","text":"회의·Log Work 용 이슈는 제목 앞에 [회의] 를 붙인다"}]
        ```
        """
}
