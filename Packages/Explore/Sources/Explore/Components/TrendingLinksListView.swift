import DesignSystem
import Models
import NetworkClient
import StatusKit
import SwiftUI

public struct TrendingLinksListView: View {
  nonisolated private static let minColumnWidth: CGFloat = 340
  nonisolated private static let columnSpacing: CGFloat = 12
  nonisolated private static let horizontalPadding: CGFloat = 16

  /// Number of columns that fit the given width. Nonisolated because `onGeometryChange` evaluates
  /// its transform off the main actor.
  nonisolated private static func columnCount(for width: CGFloat) -> Int {
    let available = width - 2 * horizontalPadding
    return max(1, Int((available + columnSpacing) / (minColumnWidth + columnSpacing)))
  }

  @Environment(Theme.self) private var theme
  @Environment(MastodonClient.self) private var client

  @State private var masonry: MasonryColumns
  @State private var heights = CardHeights()

  public init(cards: [Card]) {
    _masonry = .init(
      initialValue: MasonryColumns(
        columnCount: 1, cards: cards, heights: CardHeights(), spacing: Self.columnSpacing))
  }

  private var isCardStyle: Bool {
    #if os(visionOS)
      true
    #else
      masonry.columns.count > 1
    #endif
  }

  private func cardView(_ card: Card) -> some View {
    StatusRowCardView(card: card)
      .environment(\.isCompact, true)
      .if(isCardStyle) { view in
        view
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .withCardBackground(cornerRadius: 10)
      }
      .padding(.vertical, isCardStyle ? 0 : 8)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        heights.record(height, for: card.id)
      }
  }

  public var body: some View {
    ScrollView {
      // Lazy so that NextPageView only loads the next page once it is scrolled into view.
      LazyVStack(spacing: 0) {
        // Every column is lazy too, so only the cards near the screen exist at any time. Cards
        // are assigned to a column once, when they are loaded (see MasonryColumns), so scrolling
        // never moves them.
        HStack(alignment: .top, spacing: Self.columnSpacing) {
          ForEach(masonry.columns.indices, id: \.self) { column in
            LazyVStack(spacing: isCardStyle ? Self.columnSpacing : 0) {
              ForEach(masonry.columns[column]) { card in
                cardView(card)
              }
            }
            .frame(maxWidth: .infinity)
          }
        }
        .padding(.horizontal, Self.horizontalPadding)
        NextPageView {
          let nextPage: [Card] = try await client.get(
            endpoint: Trends.links(offset: masonry.cards.count))
          masonry.append(nextPage, heights: heights, spacing: Self.columnSpacing)
        }
        // With several columns a page can fit entirely on screen, so the loader never scrolls
        // out of view and re-appears. Recreating it per page keeps loading until the screen is
        // filled, and stops once the server returns nothing new (the count no longer changes).
        .id(masonry.cards.count)
      }
    }
    .onGeometryChange(for: Int.self) { proxy in
      Self.columnCount(for: proxy.size.width)
    } action: { newCount in
      guard newCount != masonry.columns.count else { return }
      // Heights depend on the column width, so what was measured no longer applies.
      heights.removeAll()
      masonry = MasonryColumns(
        columnCount: newCount, cards: masonry.cards, heights: heights, spacing: Self.columnSpacing)
    }
    .refreshable {
      do {
        let fresh: [Card] = try await client.get(endpoint: Trends.links(offset: nil))
        masonry = MasonryColumns(
          columnCount: masonry.columns.count, cards: fresh, heights: heights,
          spacing: Self.columnSpacing)
      } catch {}
    }
    #if !os(visionOS)
      .background(theme.primaryBackgroundColor)
    #endif
    .navigationTitle("explore.section.trending.links")
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Remembers how tall each card rendered, so new cards can be sent to the shortest column. A plain
/// reference type on purpose: recording a height must not invalidate the view.
private final class CardHeights {
  private var values: [Card.ID: CGFloat] = [:]

  func record(_ height: CGFloat, for id: Card.ID) {
    values[id] = height
  }

  func height(for id: Card.ID) -> CGFloat? {
    values[id]
  }

  func removeAll() {
    values.removeAll()
  }

  /// Stand-in for cards that have not been rendered yet.
  var average: CGFloat {
    values.isEmpty ? 260 : values.values.reduce(0, +) / CGFloat(values.count)
  }
}

/// Splits cards into columns of similar height. Each card is assigned to a column once, when it is
/// appended, using the real heights of the cards already shown, so columns stay balanced however
/// many pages are loaded and a card never changes column while it is on screen.
private struct MasonryColumns {
  private(set) var cards: [Card] = []
  private(set) var columns: [[Card]]

  init(columnCount: Int, cards: [Card], heights: CardHeights, spacing: CGFloat) {
    columns = Array(repeating: [], count: max(1, columnCount))
    append(cards, heights: heights, spacing: spacing)
  }

  mutating func append(_ newCards: [Card], heights: CardHeights, spacing: CGFloat) {
    let average = heights.average
    var totals = columns.map { column in
      column.reduce(CGFloat.zero) { $0 + (heights.height(for: $1.id) ?? average) + spacing }
    }
    for card in newCards {
      let shortest = totals.indices.min { totals[$0] < totals[$1] } ?? 0
      columns[shortest].append(card)
      totals[shortest] += average + spacing
    }
    cards.append(contentsOf: newCards)
  }
}
