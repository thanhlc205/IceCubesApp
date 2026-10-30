import DesignSystem
import Models
import NetworkClient
import SwiftUI

public struct StatusEditHistoryView: View {
  @Environment(\.dismiss) private var dismiss

  @Environment(MastodonClient.self) private var client
  @Environment(Theme.self) private var theme

  private let statusId: String

  @State private var history: [StatusHistory]?

  public init(statusId: String) {
    self.statusId = statusId
  }

  public var body: some View {
    NavigationStack {
      List {
        Section {
          if let history {
            ForEach(history) { edit in
              VStack(alignment: .leading, spacing: 8) {
                EmojiTextApp(edit.content, emojis: edit.emojis)
                  .font(.scaledBody)
                  .emojiText.size(Font.scaledBodyFont.emojiSize)
                  .emojiText.baselineOffset(Font.scaledBodyFont.emojiBaselineOffset)
                Group {
                  let createdAt = edit.createdAt.asDate
                  Text(
                    "\(createdAt, style: .date)\(Text("status.summary.at-time"))\(createdAt, style: .time)"
                  )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
              }
            }
          } else {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          }
        }.listRowBackground(theme.primaryBackgroundColor)
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("action.done", action: { dismiss() })
        }
      }
      .navigationTitle("status.summary.edit-history")
      .navigationBarTitleDisplayMode(.inline)
      .task {
        do {
          history = try await client.get(endpoint: Statuses.history(id: statusId))
        } catch {}
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(theme.primaryBackgroundColor)
    }
  }
}
