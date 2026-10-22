import Foundation

public struct ChatMessage: Identifiable, Codable, Equatable {
    public enum Role: String, Codable { case user, assistant, error }

    public let id: UUID
    public let role: Role
    public let text: String
    public let date: Date
    /// 첨부 이미지 파일 경로 (앱 데이터 폴더의 attachments/ 아래)
    public let images: [String]

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), images: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.images = images
    }

    /// 예전 대화 기록(images 없음)도 읽는다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
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
