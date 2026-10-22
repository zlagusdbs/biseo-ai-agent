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

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), images: [String] = [], alarms: [Alarm] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.images = images
        self.alarms = alarms
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
