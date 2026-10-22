import Foundation

/// 채팅으로 만든 Jira 이슈 초안. Claude 는 등록하지 않고 초안만 제안하고,
/// 사용자가 확인 카드에서 [Jira에 등록]을 눌러야 `kimbiseo jira create` 로 등록된다.
public struct JiraDraft: Codable, Equatable {
    public var project: String
    public var issueType: String
    public var summary: String
    public var description: String
    public var originalEstimate: String
    public var targetStart: String      // yyyy-MM-dd, 비우면 안 보냄
    public var targetEnd: String
    public var epicLink: String

    public init(project: String, issueType: String, summary: String, description: String,
                originalEstimate: String = "", targetStart: String = "", targetEnd: String = "", epicLink: String = "") {
        self.project = project
        self.issueType = issueType
        self.summary = summary
        self.description = description
        self.originalEstimate = originalEstimate
        self.targetStart = targetStart
        self.targetEnd = targetEnd
        self.epicLink = epicLink
    }

    /// Claude 가 일부 항목을 빼먹어도 읽는다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        project = text(.project)
        issueType = text(.issueType)
        summary = text(.summary)
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        originalEstimate = text(.originalEstimate)
        targetStart = text(.targetStart)
        targetEnd = text(.targetEnd)
        epicLink = text(.epicLink)
    }

    public var isComplete: Bool { !project.isEmpty && !issueType.isEmpty && !summary.isEmpty }

    /// 카드에 보일 기간 한 줄. 예: "2026-10-22 ~ 2026-12-31 · 365d"
    public var periodText: String {
        let period = [targetStart, targetEnd].contains { !$0.isEmpty } ? "\(targetStart.isEmpty ? "?" : targetStart) ~ \(targetEnd.isEmpty ? "?" : targetEnd)" : ""
        return [period, originalEstimate].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 등록된 이슈.
public struct JiraCreated: Codable, Equatable {
    public let key: String
    public let url: String
    public init(key: String, url: String) { self.key = key; self.url = url }
}

/// 이 PC 사용자의 Jira 등록 기본값. 앱 데이터 폴더에만 저장한다 (Git 에 올라가지 않음, 사람·PC 마다 다름).
public struct JiraDefaults: Codable, Equatable {
    public enum StartRule: String, Codable, CaseIterable { case today, none }
    public enum EndRule: String, Codable, CaseIterable { case yearEnd, none }

    public var project: String
    public var devType: String          // 개발 일
    public var taskType: String         // 그 외 일반 업무
    public var originalEstimate: String
    public var targetStart: StartRule
    public var targetEnd: EndRule
    public var epicLink: String

    public init(project: String, devType: String = "Story", taskType: String = "Task", originalEstimate: String = "365d",
                targetStart: StartRule = .today, targetEnd: EndRule = .yearEnd, epicLink: String = "") {
        self.project = project
        self.devType = devType
        self.taskType = taskType
        self.originalEstimate = originalEstimate
        self.targetStart = targetStart
        self.targetEnd = targetEnd
        self.epicLink = epicLink
    }

    /// Claude 가 일부만 보내도 나머지는 기본 규칙으로 채운다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys, _ fallback: String) -> String {
            let value = ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespaces) ?? ""
            return value.isEmpty ? fallback : value
        }
        project = text(.project, "")
        devType = text(.devType, "Story")
        taskType = text(.taskType, "Task")
        originalEstimate = ((try? c.decodeIfPresent(String.self, forKey: .originalEstimate)) ?? nil) ?? "365d"
        targetStart = StartRule(rawValue: text(.targetStart, "today")) ?? .today
        targetEnd = EndRule(rawValue: text(.targetEnd, "yearEnd")) ?? .yearEnd
        epicLink = text(.epicLink, "")
    }

    public func startDate(now: Date, calendar: Calendar) -> String {
        targetStart == .today ? ReportSchedule.dayString(now, calendar: calendar) : ""
    }

    /// 그해 12월 31일.
    public func endDate(now: Date, calendar: Calendar) -> String {
        targetEnd == .yearEnd ? "\(calendar.component(.year, from: now))-12-31" : ""
    }

    /// 사람이 읽는 한 줄. 카드·설정 화면·Claude 안내에 쓴다.
    public func summary(now: Date, calendar: Calendar) -> String {
        var parts = ["프로젝트 \(project)", "개발 일은 \(devType), 그 외는 \(taskType)"]
        if !originalEstimate.isEmpty { parts.append("Original Estimate \(originalEstimate)") }
        parts.append(targetStart == .today ? "Target start 오늘(\(startDate(now: now, calendar: calendar)))" : "Target start 없음")
        parts.append(targetEnd == .yearEnd ? "Target end 올해 마지막 날(\(endDate(now: now, calendar: calendar)))" : "Target end 없음")
        parts.append(epicLink.isEmpty ? "Epic Link 없음" : "Epic Link \(epicLink)")
        return parts.joined(separator: ", ")
    }

    public static var file: URL { AppPaths.dataDir.appendingPathComponent("jira-defaults.json") }

    public static func load() -> JiraDefaults? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(JiraDefaults.self, from: $0) }
    }

    public static func save(_ defaults: JiraDefaults?) {
        guard let defaults else { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(defaults).write(to: file, options: .atomic)
    }
}

/// 채팅 답변의 ```kimbiseo-jira 블록과, 질문에 몰래 붙이는 안내.
public enum JiraProposal {
    private struct Block: Decodable {
        let issue: JiraDraft?
        let defaults: JiraDefaults?
    }

    private static let block = try! NSRegularExpression(pattern: "```kimbiseo-jira[ \\t]*\\n(.*?)```",
                                                        options: [.dotMatchesLineSeparators])

    /// 답변에서 블록을 떼어 낸다. (보일 글, 초안, 새 기본값 제안)
    public static func extract(from text: String) -> (text: String, draft: JiraDraft?, defaults: JiraDefaults?) {
        let range = NSRange(text.startIndex..., in: text)
        var draft: JiraDraft?
        var defaults: JiraDefaults?
        if let match = block.firstMatch(in: text, range: range), let body = Range(match.range(at: 1), in: text),
           let parsed = try? JSONDecoder().decode(Block.self, from: Data(text[body].utf8)) {
            draft = parsed.issue.flatMap { $0.isComplete ? $0 : nil }
            defaults = parsed.defaults.flatMap { $0.project.isEmpty ? nil : $0 }
        }
        let clean = block.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, draft, defaults)
    }

    /// "지라/이슈/티켓" 과 "등록/만들/올려" 같은 말이 같이 있으면 이슈 등록 요청일 수 있다고 본다.
    public static func looksLikeRequest(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        let things = ["jira", "지라", "이슈", "티켓", "일감", "스토리", "story", "task"]
        let actions = ["등록", "만들", "생성", "올려", "작성", "발행", "추가", "따줘", "끊어"]
        return things.contains { compact.contains($0) } && actions.contains { compact.contains($0) }
    }

    /// 질문 끝에 몰래 붙이는 안내 (화면에는 보이지 않음). 기본값이 없으면 먼저 물어보게 한다.
    public static func hint(defaults: JiraDefaults?, now: Date, calendar: Calendar) -> String {
        let today = ReportSchedule.dayString(now, calendar: calendar)
        let common = """
            Jira 이슈 등록 요청이면 직접 등록하지 말고(등록 도구 없음, 거절도 하지 않음) 답변 끝에 kimbiseo-jira 블록으로 초안을 붙인다. \
            앱이 확인 카드와 [Jira에 등록] 버튼을 보여 주고, 사용자가 눌러야 등록된다. 오늘은 \(today). \
            summary 는 지시 내용을 짧고 명확한 제목으로, description 은 Jira 위키 문법(h3. 제목, * 목록, # 번호)으로 \
            배경·할 일·완료 조건을 보기 좋게 정리한다. 개발 일이면 개발용 유형, 아니면 일반 업무 유형을 고른다. \
            본문은 초안을 한두 줄로 요약하고 "아래 카드에서 확인하고 [Jira에 등록]을 누르면 등록돼요" 로 끝낸다. \
            이 안내는 사용자에게 보이지 않으니 언급하지 않는다.
            """
        let body: String
        if let defaults {
            body = """
                기본값: \(defaults.summary(now: now, calendar: calendar)). 사용자가 따로 말한(강조한) 항목만 이번 이슈에서 바꾼다. \
                "앞으로", "기본값" 처럼 기본값 자체를 바꾸라고 하면 블록에 "defaults" 도 넣는다.
                ```kimbiseo-jira
                {"issue":{"project":"\(defaults.project)","issueType":"\(defaults.devType)","summary":"제목","description":"h3. 배경\\n...",\
                "originalEstimate":"\(defaults.originalEstimate)","targetStart":"\(defaults.startDate(now: now, calendar: calendar))",\
                "targetEnd":"\(defaults.endDate(now: now, calendar: calendar))","epicLink":"\(defaults.epicLink)"}}
                ```
                """
        } else {
            body = """
                이 사용자의 기본값이 아직 없다. 처음이므로 프로젝트, 이슈 유형(개발 일/일반 업무), Original Estimate, \
                Target start 규칙(오늘/없음), Target end 규칙(올해 마지막 날/없음), Epic Link 를 먼저 물어보고 블록은 붙이지 않는다. \
                사용자가 이미 다 말했으면 묻지 않는다. 프로젝트 이름을 말하면 jira_projects 로 키를 찾아 확인한다 (예: 이름과 키가 다를 수 있다). \
                정해지면 다음 답변부터 이슈 블록에 기본값도 함께 넣는다 (targetStart 는 today|none, targetEnd 는 yearEnd|none).
                ```kimbiseo-jira
                {"issue":{"project":"KEY","issueType":"Story","summary":"제목","description":"h3. 배경\\n...","originalEstimate":"365d",\
                "targetStart":"\(today)","targetEnd":"\(calendar.component(.year, from: now))-12-31","epicLink":""},\
                "defaults":{"project":"KEY","devType":"Story","taskType":"Task","originalEstimate":"365d","targetStart":"today","targetEnd":"yearEnd","epicLink":""}}
                ```
                """
        }
        return "\n\n[김비서 앱 안내: \(common)\n\(body)]"
    }
}
