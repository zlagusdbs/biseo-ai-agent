import SwiftUI

/// 왼쪽은 선택한 메뉴 내용, 오른쪽은 세로 메뉴(채팅·연결·설정).
struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch model.selected {
                case .chat: ChatView(model: model, chat: model.chat)
                case .connections: ConnectionsView(model: model)
                case .alarms: AlarmsView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 6) {
                ForEach(SidebarItem.allCases) { item in
                    Button {
                        model.selected = item
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(model.selected == item ? Color.accentColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(item.title)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .frame(width: 52)
        }
        .frame(minWidth: 420, idealWidth: 540, maxWidth: .infinity, minHeight: 420, idealHeight: 620, maxHeight: .infinity)
    }
}
