import Foundation

public struct ChatMessage: Identifiable, Codable, Equatable {
    public enum Role: String, Codable { case user, assistant, error }

    public let id: UUID
    public let role: Role
    public let text: String
    public let date: Date
    /// 첨부 이미지 파일 경로 (앱 데이터 폴더의 attachments/ 아래)
    public let images: [String]
    /// 답변이 등록을 제안한 알림 (사용자가 버튼을 눌러야 등록된다)
    public let alarms: [Alarm]
    /// 답변이 제안한 Jira 이슈 초안 (카드에서 고칠 수 있음)과 등록 결과
    public var jira: JiraDraft?
    public var jiraCreated: JiraCreated?
    /// 답변이 제안한 규칙과 저장 여부
    public var rules: [RuleNote] = []
    public var rulesSaved = false
    /// 답변이 제안한 worklog 와 기록 끝난 것(id)
    public var worklogs: [WorklogDraft] = []
    public var worklogsDone: [String] = []

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), images: [String] = [], alarms: [Alarm] = [],
                jira: JiraDraft? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.images = images
        self.alarms = alarms
        self.jira = jira
    }

    /// 예전 대화 기록(images·alarms 없음)도 읽는다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        alarms = try c.decodeIfPresent([Alarm].self, forKey: .alarms) ?? []
        jira = try c.decodeIfPresent(JiraDraft.self, forKey: .jira)
        jiraCreated = try c.decodeIfPresent(JiraCreated.self, forKey: .jiraCreated)
        rules = try c.decodeIfPresent([RuleNote].self, forKey: .rules) ?? []
        rulesSaved = try c.decodeIfPresent(Bool.self, forKey: .rulesSaved) ?? false
        worklogs = try c.decodeIfPresent([WorklogDraft].self, forKey: .worklogs) ?? []
        worklogsDone = try c.decodeIfPresent([String].self, forKey: .worklogsDone) ?? []
    }
}

/// Claude 에게 보낼 이미지 한 장.
public struct ImageAttachment: Equatable {
    public let mediaType: String   // image/png, image/jpeg ...
    public let data: Data
    public let path: String        // 화면 표시용 저장 위치

    public init(mediaType: String, data: Data, path: String) {
        self.mediaType = mediaType
        self.data = data
        self.path = path
    }
}
