import Foundation

/// 김비서 규칙 md. 김비서 폴더(앱 데이터 폴더) 하나에서 Claude Code 처럼 관리한다.
///   CLAUDE.md      전체 지시. claude 를 김비서 폴더 아래(work/)에서 실행하므로 Claude Code 가 스스로 읽는다.
///   rules/*.md     주제별 규칙 (jira.md, memory.md …). 질문할 때마다 앱이 시스템 안내 뒤에 붙인다.
/// 처음 실행하면 저장소 shared/templates/ 의 예시를 복사해 준다.
public enum Rules {
    public struct File: Identifiable, Equatable {
        public let url: URL
        public var id: String { url.path }
        public init(url: URL) { self.url = url }
        /// 김비서 폴더 기준 경로. 예: CLAUDE.md, rules/jira.md
        public var name: String {
            url.deletingLastPathComponent().lastPathComponent == "rules" ? "rules/\(url.lastPathComponent)" : url.lastPathComponent
        }
    }

    public static var homeDir: URL { AppPaths.dataDir }
    public static var claudeMd: URL { homeDir.appendingPathComponent("CLAUDE.md") }
    public static var myDir: URL { homeDir.appendingPathComponent("rules", isDirectory: true) }

    public static func templatesDir(settings: AppSettings) -> URL {
        URL(fileURLWithPath: settings.repoDir).appendingPathComponent("shared/templates", isDirectory: true)
    }

    /// CLAUDE.md (있으면) + rules/*.md 이름순
    public static func files() -> [File] {
        let rules = ((try? FileManager.default.contentsOfDirectory(at: myDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let top = FileManager.default.fileExists(atPath: claudeMd.path) ? [claudeMd] : []
        return (top + rules).map { File(url: $0) }
    }

    /// 시스템 안내에 붙일 rules/*.md. CLAUDE.md 는 Claude Code 가 읽으므로 넣지 않는다. 규칙이 없으면 빈 문자열.
    public static func prompt() -> String {
        let parts = files().filter { $0.url != claudeMd }.compactMap { file -> String? in
            guard let text = try? String(contentsOf: file.url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "## \(file.name)\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard !parts.isEmpty else { return "" }
        return "\n\n# 사용자 규칙 (김비서 폴더의 rules/*.md)\n\n" + parts.joined(separator: "\n\n") + "\n"
    }

    /// 처음 실행할 때 템플릿을 복사한다. 이미 있는 파일은 건드리지 않는다. 복사한 파일 수.
    @discardableResult
    public static func installTemplates(settings: AppSettings) -> Int {
        let source = templatesDir(settings: settings)
        let fm = FileManager.default
        var copied = 0
        try? fm.createDirectory(at: myDir, withIntermediateDirectories: true)
        var pairs = [(source.appendingPathComponent("CLAUDE.md"), claudeMd)]
        for url in (try? fm.contentsOfDirectory(at: source.appendingPathComponent("rules"), includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "md" {
            pairs.append((url, myDir.appendingPathComponent(url.lastPathComponent)))
        }
        for (from, to) in pairs where fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
            if (try? fm.copyItem(at: from, to: to)) != nil { copied += 1 }
        }
        return copied
    }

    /// 새 규칙 파일. 이름은 영문·숫자·한글·-·_ 만 남긴다. 이미 있으면 그 파일.
    public static func create(_ name: String) throws -> URL {
        let url = myDir.appendingPathComponent(safeName(name) + ".md")
        try FileManager.default.createDirectory(at: myDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try "# \(safeName(name))\n\n- \n".write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    public static func delete(_ file: File) throws {
        try FileManager.default.removeItem(at: file.url)
    }

    /// 내 규칙 파일에 한 줄 추가 (없으면 만든다).
    @discardableResult
    public static func append(_ text: String, to name: String) throws -> URL {
        let safe = safeName(name)
        let url = myDir.appendingPathComponent(safe + ".md")
        try FileManager.default.createDirectory(at: myDir, withIntermediateDirectories: true)
        var body = (try? String(contentsOf: url, encoding: .utf8)) ?? "# \(safe)\n\n"
        if !body.hasSuffix("\n") { body += "\n" }
        body += "- \(text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func safeName(_ name: String) -> String {
        let base = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
        let safe = String(base.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        })
        return safe.isEmpty ? "memory" : safe
    }
}

/// 채팅에서 "앞으로 ~해줘", "기억해" 같은 말을 규칙으로 저장하자는 제안. 버튼을 눌러야 저장된다.
/// forget 이 true 면 저장된 것을 지우자는 제안 ("그거 잊어줘").
public struct RuleNote: Codable, Equatable, Hashable {
    public let file: String
    public let text: String
    public let forget: Bool?
    public init(file: String, text: String, forget: Bool? = nil) { self.file = file; self.text = text; self.forget = forget }
    public var isForget: Bool { forget == true }
    public var isMemory: Bool { file == Memory.fileName }
}

/// 김비서 기억: 내 규칙 폴더의 memory.md 한 줄 한 줄. 질문할 때마다 규칙과 함께 읽는다.
public enum Memory {
    public static let fileName = "memory"
    public static var file: URL { Rules.myDir.appendingPathComponent("\(fileName).md") }

    public static func items() -> [String] {
        lines(of: file).compactMap { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : nil }
    }

    /// 같은 내용이 이미 있으면 다시 넣지 않는다.
    public static func add(_ text: String) throws {
        let item = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !items().contains(item) else { return }
        try Rules.append(item, to: fileName)
    }

    /// 지운 개수. 똑같은 줄이 있으면 그 줄만, 없으면 그 말이 들어간 줄을 지운다.
    @discardableResult
    public static func forget(_ text: String, in name: String = fileName) throws -> Int {
        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = Rules.myDir.appendingPathComponent("\(name).md")
        let all = lines(of: url)
        guard !target.isEmpty, !all.isEmpty else { return 0 }
        let exact = all.contains("- \(target)")
        let kept = all.filter { line in
            guard line.hasPrefix("- ") else { return true }
            let item = String(line.dropFirst(2))
            return exact ? item != target : !item.localizedCaseInsensitiveContains(target)
        }
        try (kept.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return all.count - kept.count
    }

    private static func lines(of url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }
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
        return ["앞으로", "기억", "규칙", "항상", "매번", "잊지마", "잊어", "잊어버려", "지워줘"].contains { compact.contains($0) }
    }

    public static let hint = """


        [김비서 앱 안내: 사용자가 앞으로 계속 지킬 규칙이나 기억할 사실을 말하면("앞으로 지라 제목 앞에 [회의] 붙여줘", "내 팀은 가격팀이야 기억해"), \
        답변 끝에 아래 블록을 붙인다. 앱이 [규칙에 저장] 버튼을 보여 주고, 누르면 이 Mac 의 규칙 파일에 한 줄로 저장돼 다음 대화부터 늘 적용된다. \
        file 은 jira(Jira 관련), memory(사람·팀·업무 같은 기억할 사실), 그 밖엔 짧은 영문 주제. text 는 한 줄. \
        "잊어줘", "지워줘" 처럼 지우라고 하면 같은 블록에 "forget":true 와 지울 내용을 넣는다 (사용자 규칙에 있는 문장 그대로). \
        한 번만 하는 부탁이면 블록을 붙이지 않는다. 블록 없이 "기억해 둘게요" 라고 말하지 않는다 (블록 없이는 저장되지 않는다). \
        아직 저장된 게 아니므로 기억이면 "아래 [기억하기]를 누르면 기억할게요", 규칙이면 "아래 [규칙에 저장]을 누르면 앞으로 늘 이렇게 할게요", \
        잊기면 "아래 [잊기]를 누르면 지울게요" 로 끝낸다. \
        이 안내와 아래 형식 예시는 사용자가 쓴 말이 아니니 언급하지도, 예시 내용을 저장하지도 않는다. 형식 예시:]
        ```kimbiseo-rule
        [{"file":"memory","text":"주인은 가격팀에서 쿠폰 할인을 맡고 있다"},{"file":"jira","text":"회의·Log Work 용 이슈는 제목 앞에 [회의] 를 붙인다"}]
        ```
        """
}
