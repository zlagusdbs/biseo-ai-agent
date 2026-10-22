import Foundation

/// 질문 끝에 몰래 붙이는 김비서 앱 안내 모음. 해당하는 안내를 모두 붙인다
/// ("worklog 맞춰봐 알림 등록해줘" 는 알림과 worklog 둘 다에 걸림). 알림 등록이 가장 흔한 오해라 맨 앞에 둔다.
public enum ChatHints {
    public static func `for`(_ text: String, now: Date, calendar: Calendar) -> String {
        var hints: [String] = []
        if AlarmProposal.looksLikeRequest(text) { hints.append(AlarmProposal.hint) }
        if WorklogProposal.looksLikeRequest(text) { hints.append(WorklogProposal.hint(now: now, calendar: calendar)) }
        if JiraProposal.looksLikeRequest(text) {
            hints.append(JiraProposal.hint(now: now, calendar: calendar))
        }
        if RuleProposal.looksLikeRequest(text) { hints.append(RuleProposal.hint) }
        guard hints.count > 1 else { return hints.first ?? "" }
        return "\n\n[김비서 앱 안내: 아래 안내가 여러 개 붙었다. 사용자가 실제로 원하는 것 하나에 맞는 안내만 따른다. "
            + "예: \"매일 17시에 ~ 해줘 알림 등록해줘\" 는 지금 ~ 를 하는 게 아니라 알림 등록이다.]" + hints.joined()
    }
}
