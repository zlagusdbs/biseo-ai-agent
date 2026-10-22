import SwiftUI

/// 편집 화면(알림 수정, Jira 이슈 수정) 색. 고칠 수 있는 칸은 흰색, 칸을 담는 카드는 한 톤 짙은 회색.
enum EditorStyle {
    static let card = Color(white: 0.925)
    static let field = Color.white
    static let border = Color.black.opacity(0.15)
}

extension View {
    /// 고칠 수 있는 글자 칸: 흰 바탕 + 얇은 테두리
    func whiteField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(EditorStyle.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(EditorStyle.border))
    }

    /// 폼 섹션 카드를 회색으로
    func grayCard() -> some View {
        listRowBackground(EditorStyle.card)
    }
}
