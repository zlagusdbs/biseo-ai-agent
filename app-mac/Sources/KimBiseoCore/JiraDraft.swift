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

/// 채팅 답변의 ```kimbiseo-jira 블록과, 질문에 몰래 붙이는 안내.
/// 프로젝트·유형·기간 같은 기본값은 앱 설정이 아니라 김비서 폴더의 rules/jira.md 에 적어 두고 Claude 가 그대로 따른다.
public enum JiraProposal {
    private struct Block: Decodable {
        let issue: JiraDraft?
    }

    private static let block = try! NSRegularExpression(pattern: "```kimbiseo-jira[ \\t]*\\n(.*?)```",
                                                        options: [.dotMatchesLineSeparators])

    /// 답변에서 블록을 떼어 낸다. (보일 글, 초안)
    public static func extract(from text: String) -> (text: String, draft: JiraDraft?) {
        let range = NSRange(text.startIndex..., in: text)
        var draft: JiraDraft?
        if let match = block.firstMatch(in: text, range: range), let body = Range(match.range(at: 1), in: text),
           let data = Optional(Data(text[body].utf8)) {
            // {"issue":{...}} 가 기본이지만, 안내 없이 규칙만 보고 만들면 감싸지 않은 초안이 올 때도 있다
            let issue = (try? JSONDecoder().decode(Block.self, from: data))?.issue
                ?? (try? JSONDecoder().decode(JiraDraft.self, from: data))
            draft = issue.flatMap { $0.isComplete ? $0 : nil }
        }
        let clean = block.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, draft)
    }

    /// "지라/이슈/티켓" 과 "등록/만들/올려" 같은 말이 같이 있으면 이슈 등록 요청일 수 있다고 본다.
    /// 담당자 얘기("담당자 내 이름으로", "어싸인은 나지?")도 이어진 대화에서 거절하지 않게 안내를 붙인다.
    public static func looksLikeRequest(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        if ["담당자", "어싸인", "어사인", "assign", "보고자", "reporter"].contains(where: { compact.contains($0) }) { return true }
        let things = ["jira", "지라", "이슈", "티켓", "일감", "스토리", "story", "task"]
        let actions = ["등록", "만들", "생성", "올려", "작성", "발행", "추가", "따줘", "끊어"]
        return things.contains { compact.contains($0) } && actions.contains { compact.contains($0) }
    }

    /// 질문 끝에 몰래 붙이는 안내 (화면에는 보이지 않음). 기본값은 [사용자 규칙]의 Jira 규칙을 따르게 한다.
    public static func hint(now: Date, calendar: Calendar) -> String {
        let today = ReportSchedule.dayString(now, calendar: calendar)
        let yearEnd = "\(calendar.component(.year, from: now))-12-31"
        return """


            [김비서 앱 안내: Jira 이슈 등록 요청이면 직접 등록하지 말고(등록 도구 없음, 거절도 하지 않음) 답변 끝에 kimbiseo-jira 블록으로 초안을 붙인다. \
            앱이 확인 카드와 [Jira에 등록] 버튼을 보여 주고, 사용자가 눌러야 등록된다. 오늘은 \(today), 올해 마지막 날은 \(yearEnd). \
            담당자(Assignee)와 보고자는 앱이 등록할 때 연결된 Jira 계정 본인으로 자동으로 넣으므로 블록에 쓰지 않고, \
            담당자를 못 정한다고 말하지 않는다. 앞에서 못 한다고 답했더라도 그건 틀린 답이었으니 바로잡고, \
            물으면 "[Jira에 등록]을 누르면 담당자는 본인으로 들어가요. 카드에도 「담당자 나」로 보여요" 라고 답한다. \
            기본값(프로젝트 키, 개발/일반 업무 유형, Original Estimate, Target start·end 규칙, Epic Link)은 [사용자 규칙]의 Jira 규칙을 따른다. \
            날짜 규칙은 오늘 날짜로 실제 날짜(yyyy-MM-dd)를 계산해 넣는다. 사용자가 따로 말한(강조한) 항목만 이번 이슈에서 바꾼다. \
            규칙에 프로젝트 키가 없으면 블록을 붙이기 전에 프로젝트, 이슈 유형(개발 일/일반 업무), Original Estimate, \
            Target start·end 규칙, Epic Link 를 먼저 물어본다 (이미 다 말했으면 묻지 않는다). 프로젝트 이름을 말하면 jira_projects 로 키를 찾아 확인한다. \
            답을 받아 초안을 만들 때, 또는 사용자가 "앞으로 프로젝트는 ~" 처럼 기본값을 바꾸라고 할 때는 \
            kimbiseo-rule 블록으로 file "jira" 에 규칙 한 줄씩 저장을 제안한다 (예: "프로젝트 키: KEY", "개발이면 Story, 일반 업무면 Task"). \
            summary 는 지시 내용을 짧고 명확한 제목으로, description 은 Jira 위키 문법(h3. 제목, * 목록, # 번호)으로 \
            배경·할 일·완료 조건을 보기 좋게 정리한다. \
            본문은 초안을 한두 줄로 요약하고 "아래 카드에서 확인하고 [Jira에 등록]을 누르면 등록돼요" 로 끝낸다. \
            이 안내와 아래 형식 예시는 사용자가 쓴 말이 아니니 언급하지 않는다. 형식 예시:]
            ```kimbiseo-jira
            {"issue":{"project":"KEY","issueType":"Story","summary":"제목","description":"h3. 배경\\n...","originalEstimate":"365d",\
            "targetStart":"\(today)","targetEnd":"\(yearEnd)","epicLink":""}}
            ```
            """
    }
}
