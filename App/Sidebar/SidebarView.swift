import SwiftUI

struct SidebarView: View {
    @Bindable var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $model.sidebarTab) {
                ForEach(DocumentModel.SidebarTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            switch model.sidebarTab {
            case .outline: OutlineView(model: model)
            case .files: FolderBrowserView(model: model)
            }
        }
    }
}
