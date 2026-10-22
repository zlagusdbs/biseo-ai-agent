import Foundation

/// `claude -p` 실행 인자. 허용 도구 목록(김비서 MCP + Microsoft 365 조회)만 쓰도록 제한한다.
public enum ClaudeCommand {
    public static let allowedTools = [
        "mcp__kimbiseo__jira_search",
        "mcp__kimbiseo__jira_projects",
        "mcp__kimbiseo__jira_my_worklogs",
        "mcp__kimbiseo__work_day_check",
        "mcp__kimbiseo__wiki_search",
        "mcp__kimbiseo__wiki_get_page",
        "mcp__kimbiseo__hr_holidays",
        "mcp__kimbiseo__hr_flexwork_week",
        "mcp__kimbiseo__deploy_my_releases",
        "mcp__kimbiseo__deploy_approvals",
        "mcp__kimbiseo__deploy_domain_releases",
        "mcp__kimbiseo__deploy_release_search",
        "mcp__kimbiseo__github_review_requests",
    ] + microsoft365Tools

    /// claude.ai 의 Microsoft 365 커넥터 (메일·일정·Teams·SharePoint). 모두 조회용 도구다.
    public static let microsoft365Tools = [
        "get_me", "outlook_email_search", "outlook_calendar_search", "outlook_find_available_time",
        "find_meeting_availability", "search_people", "read_resource", "get_granted_scopes",
        "teams_list_teams", "teams_list_channels", "teams_list_channel_messages", "teams_list_chats",
        "chat_message_search", "sharepoint_search", "sharepoint_folder_search",
    ].map { "mcp__claude_ai_Microsoft_365__\($0)" }

    /// 질문과 이미지는 인자가 아니라 표준 입력(`inputLine`)으로 보낸다.
    public static func arguments(sessionId: String?, mcpConfigPath: String, systemPrompt: String) -> [String] {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--mcp-config", mcpConfigPath,         // 김비서 MCP 서버. claude.ai 커넥터(Microsoft 365)도 함께 쓰려고 strict 는 쓰지 않는다
            "--tools", "",                       // 파일 읽기·쓰기, 터미널 등 기본 도구를 모두 끈다
            "--allowedTools", allowedTools.joined(separator: ","),
            "--setting-sources", "project",       // 평소 쓰는 플러그인·훅(사용자 설정)을 불러오지 않는다
            "--append-system-prompt", systemPrompt,
        ]
        if let sessionId, !sessionId.isEmpty {
            args += ["--resume", sessionId]
        }
        return args
    }

    /// 표준 입력으로 보낼 사용자 메시지 한 줄 (이미지 먼저, 질문 뒤).
    public static func inputLine(prompt: String, images: [ImageAttachment]) -> String {
        var content: [[String: Any]] = images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": prompt])
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
        let data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
