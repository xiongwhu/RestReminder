// SPDX-License-Identifier: CPAL-1.0
//
// EXHIBIT A. Common Public Attribution License Version 1.0.
//
// The contents of this file are subject to the Common Public Attribution License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at https://opensource.org/license/cpal-1-0. The License is based on the Mozilla Public License Version 1.1 but Sections 14 and 15 have been added to cover use of software over a computer network and provide for limited attribution for the Original Developer. In addition, Exhibit A has been modified to be consistent with Exhibit B.
//
// Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.
//
// The Original Code is RestReminder (歇一会儿), including the original source code, tests and build scripts distributed in this repository. Third-party photographs identified in Resources/PHOTO-CREDITS.md are excluded and remain subject to their original licenses.
// The Initial Developer of the Original Code is 广州迈润网络科技有限公司 (迈润智人 RaCIO).
// The Original Developer is the Initial Developer.
// All portions of the code written by the Initial Developer are Copyright (c) 2026 广州迈润网络科技有限公司. All Rights Reserved.
// Contributor(s): see individual source notices and project history.
// No alternative license is designated for the Original Code.
//
// [NOTE: The text of this Exhibit A may differ slightly from the text of the notices in the Source Code files of the Original Code. You should use the text of this Exhibit A rather than the text found in the Original Code Source Code for Your Modifications.]
//
// For Exhibit B Attribution Information, see the root LICENSE file.

import AppKit

/// The Settings footer. Creating or laying out this view never opens a website.
final class AboutBrandView: NSView {
    static let websiteURL = URL(string: "https://www.racio.chat")!

    private let openWebsite: (URL) -> Void
    private let content = NSStackView()
    private var wrappingLabels: [NSTextField] = []

    init(openWebsite: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.openWebsite = openWebsite
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("aboutBrand")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("关于歇一会儿")

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.setHuggingPriority(.required, for: .vertical)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let divider = NSBox()
        divider.boxType = .separator
        content.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(12, after: divider)

        let heading = label("关于歇一会儿", size: 13, weight: .semibold, color: .labelColor)
        let website = NSButton(title: "访问官网 racio.chat ↗", target: self, action: #selector(visitWebsite))
        website.bezelStyle = .rounded
        website.font = .systemFont(ofSize: 13)
        website.toolTip = Self.websiteURL.absoluteString
        website.identifier = NSUserInterfaceItemIdentifier("aboutWebsiteButton")
        website.setAccessibilityLabel("访问迈润智人 RaCIO 官网")
        website.setAccessibilityHelp(Self.websiteURL.absoluteString)
        website.setContentHuggingPriority(.required, for: .horizontal)
        website.setContentCompressionResistancePriority(.required, for: .horizontal)
        let headingRow = NSStackView(views: [heading, NSView(), website])
        headingRow.alignment = .centerY
        headingRow.spacing = 8
        content.addArrangedSubview(headingRow)
        headingRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        content.setCustomSpacing(10, after: headingRow)

        let attribution = label("RestReminder by RaCIO", size: 11)
        let license = label("CPAL-1.0", size: 11)
        license.toolTip = "开源许可：Common Public Attribution License 1.0"
        license.setAccessibilityLabel("开源许可 CPAL-1.0")
        let attributionRow = NSStackView(views: [attribution, NSView(), license])
        attributionRow.alignment = .firstBaseline
        attributionRow.spacing = 8
        content.addArrangedSubview(attributionRow)
        attributionRow.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        addWrappingLabel("Copyright (c) 2026 迈润智人", size: 11)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        // AppKit needs the current width to derive multiline label heights.
        let width = bounds.width
        if width > 0 {
            for label in wrappingLabels where abs(label.preferredMaxLayoutWidth - width) > 0.5 {
                label.preferredMaxLayoutWidth = width
                label.invalidateIntrinsicContentSize()
            }
        }
        super.layout()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .secondaryLabelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    @discardableResult
    private func addWrappingLabel(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 408
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        content.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        wrappingLabels.append(label)
        return label
    }

    @objc private func visitWebsite() { openWebsite(Self.websiteURL) }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A top-aligned settings document that grows with arranged views, including hidden tools.
final class SettingsScrollContainer: NSScrollView {
    private let stack: NSStackView

    /// The content's natural height, independent of the current viewport height.
    var preferredContentHeight: CGFloat { stack.fittingSize.height + 48 }

    init(stack: NSStackView) {
        self.stack = stack
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .legacy // A reserved gutter keeps controls clear of the scrollbar.
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .automatic

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        documentView = document
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.detachesHiddenViews = true
        stack.setHuggingPriority(.required, for: .vertical)
        document.addSubview(stack)
        // The flipped document stays at the top even when shorter than the viewport.
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            document.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 24)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func scrollToTop() {
        layoutSubtreeIfNeeded()
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }
}
