import Models
import SwiftUI

/// A utility that creates a suitable combined accessibility label for a `StatusRowView` that is not focused.
@MainActor
struct StatusRowAccessibilityLabel {
  let viewModel: StatusRowViewModel

  var hasSpoiler: Bool {
    viewModel.displaySpoiler && viewModel.finalStatus.spoilerText.asRawText.isEmpty == false
  }

  var isReply: Bool {
    if let accountId = viewModel.status.inReplyToAccountId,
      viewModel.status.mentions.contains(where: { $0.id == accountId })
    {
      return true
    }
    return false
  }

  var isBoost: Bool {
    viewModel.status.reblog != nil
  }

  var filter: Filter? {
    guard viewModel.isFiltered else {
      return nil
    }
    return viewModel.filter?.filter
  }

  func finalLabel() -> Text {
    if let filter {
      switch filter.filterAction {
      case .warn:
        return Text("status.filter.filtered-by-\(filter.title)")
      case .hide:
        return Text("")
      }
    }

    let status = viewModel.finalStatus
    let content = Text(hasSpoiler ? status.spoilerText.asRawText : status.content.asRawText)
    let spoilerLabel = Text(hasSpoiler ? "status.editor.spoiler" : "")
    let createdAt = Text(status.createdAt.relativeFormatted)
    let replies = Text("status.summary.n-replies \(status.repliesCount)")
    let boosts = Text("status.summary.n-boosts \(status.reblogsCount)")
    let favorites = Text("status.summary.n-favorites \(status.favouritesCount)")

    return Text(
      "\(userNamePreamble())\(content)\(spoilerLabel), \(pollText())\(imageAltText())\(createdAt), \(replies), \(boosts), \(favorites)"
    )
  }

  func userNamePreamble() -> Text {
    switch (isReply, isBoost) {
    case (true, false):
      let repliedTo = Text("accessibility.status.a-replied-to-\(finalUserDisplayName())")
      return Text("\(repliedTo) ")
    case (_, true):
      let boosted = Text(
        "accessibility.status.a-boosted-b-\(userDisplayName())-\(finalUserDisplayName())")
      return Text("\(boosted), ")
    default:
      return Text("\(Text(userDisplayName())), ")
    }
  }

  func userDisplayName() -> String {
    viewModel.status.account.displayNameWithoutEmojis.count < 4
      ? viewModel.status.account.safeDisplayName
      : viewModel.status.account.displayNameWithoutEmojis
  }

  func finalUserDisplayName() -> String {
    viewModel.finalStatus.account.displayNameWithoutEmojis.count < 4
      ? viewModel.finalStatus.account.safeDisplayName
      : viewModel.finalStatus.account.displayNameWithoutEmojis
  }

  func imageAltText() -> Text {
    let descriptions = viewModel.finalStatus.mediaAttachments
      .compactMap(\.description)

    if descriptions.count == 1 {
      let altText = Text("accessibility.image.alt-text-\(descriptions[0])")
      return Text("\(altText), ")
    } else if descriptions.count > 1 {
      let altText = Text("accessibility.image.alt-text-\(descriptions[0])")
      let more = Text("accessibility.image.alt-text-more.label")
      return Text("\(altText), \(more), ")
    } else if viewModel.finalStatus.mediaAttachments.isEmpty == false {
      let differentTypes = Set(
        viewModel.finalStatus.mediaAttachments.compactMap(\.localizedTypeDescription)
      ).sorted()
      let containsMedia = Text(
        "accessibility.status.contains-media.label-\(ListFormatter.localizedString(byJoining: differentTypes))"
      )
      return Text("\(containsMedia), ")
    } else {
      return Text("")
    }
  }

  func pollText() -> Text {
    if let poll = viewModel.finalStatus.poll {
      let showPercentage = poll.expired || poll.voted ?? false
      let title: LocalizedStringKey =
        poll.expired
        ? "accessibility.status.poll.finished.label"
        : "accessibility.status.poll.active.label"

      return poll.options.enumerated().reduce(into: Text(title)) { text, pair in
        let (index, option) = pair
        let selected = poll.ownVotes?.contains(index) ?? false
        let percentage =
          poll.safeVotersCount > 0 && option.votesCount != nil
          ? Int(round(Double(option.votesCount!) / Double(poll.safeVotersCount) * 100))
          : 0

        let selectedLabel = Text(selected ? "accessibility.status.poll.selected.label" : "")
        let optionPrefix = Text(
          "accessibility.status.poll.option-prefix-\(index + 1)-of-\(poll.options.count)")
        let optionTitle = Text(option.title)
        let optionPercentage = Text(showPercentage ? ", \(percentage)%. " : ". ")

        text = Text("\(text)\(selectedLabel), \(optionPrefix), \(optionTitle)\(optionPercentage)")
      }
    }
    return Text("")
  }
}
