//
//  PaywallComponents.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI

/// Geometry for the upgrade dialog, taken from the design's 880×680 frame.
enum PaywallMetrics {
    static let dialogSize = CGSize(width: 880, height: 680)
    static let horizontalPadding: CGFloat = 40
    static let topPadding: CGFloat = 28
    static let bottomPadding: CGFloat = 20
    /// The hero band: the pitch beside the preview plate.
    static let heroHeight: CGFloat = 366
    static let heroSpacing: CGFloat = 40
    static let previewWidth: CGFloat = 340
    static let previewRadius: CGFloat = 24
    static let planHeight: CGFloat = 104
    static let planSpacing: CGFloat = 14
    static let actionSize = CGSize(width: 400, height: 52)
}

// MARK: - Plan Card

/// One plan in the grid: its name, price, caption and selection ring.
///
/// Everything printed here arrives from `IAPManager`, so a price or a trial
/// changed in App Store Connect reads through without a code change.
struct PaywallPlanCard: View {
    let plan: PremiumProductId
    let isSelected: Bool
    /// "Most Popular" / "Best Value" — design decoration, not store data.
    var badge: PaywallBadge?
    let price: String
    let period: String
    let caption: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(plan.planTitle)
                        .grokText(.fileTitle, color: GrokColor.black1)
                    Spacer(minLength: 0)
                    PaywallRadio(isSelected: isSelected)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(price)
                            .grokText(.paywallPrice, color: GrokColor.black1)
                        Text(period)
                            .grokText(.paywallDetail, color: GrokColor.black6)
                    }

                    if let caption {
                        Text(caption)
                            .grokText(.metadata, color: GrokColor.black6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: PaywallMetrics.planHeight)
            .background(
                RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                    .fill(GrokColor.white1)
            )
            // Selection draws a ring outside the card, the unselected state a
            // hairline inside it, which is how the design separates the two.
            .overlay(
                RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? GrokColor.black1 : GrokColor.white4,
                        lineWidth: isSelected ? 2 : 1
                    )
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .topLeading) {
                if let badge {
                    badge.label
                        .padding(.leading, 18)
                        .offset(y: -11)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous))
        }
        .buttonStyle(GrokButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// The pill that sits astride a card's top edge.
struct PaywallBadge {
    let title: String
    let background: Color
    let foreground: Color

    /// Computed, not stored: a stored constant would capture its text in the
    /// language the app launched in and keep it after a language change.
    static var mostPopular: PaywallBadge { PaywallBadge(
        title: "paywall.badge.popular".localized,
        background: GrokColor.black1,
        foreground: GrokColor.white1
    ) }

    static var bestValue: PaywallBadge { PaywallBadge(
        title: "paywall.badge.value".localized,
        background: GrokColor.white4,
        foreground: GrokColor.black1
    ) }

    /// Which badge a plan wears. Only the longest plan can claim best value,
    /// and only when it is not the one being pushed as most popular.
    static func forPlan(_ plan: PremiumProductId) -> PaywallBadge? {
        switch plan {
        case .monthly: return .mostPopular
        case .yearly: return .bestValue
        case .weekly: return nil
        }
    }

    var label: some View {
        Text(title)
            .grokText(.paywallBadge, color: foreground)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(background))
    }
}

/// The card's selection dot: a filled disc with a check, or an empty ring.
private struct PaywallRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? GrokColor.black1 : .clear)
            if !isSelected {
                Circle()
                    .strokeBorder(GrokColor.white6, lineWidth: 1.5)
            }
            SymbolIcon("checkmark", size: 10, weight: .bold, color: GrokColor.white1)
                .opacity(isSelected ? 1 : 0)
        }
        .frame(width: 20, height: 20)
    }
}

/// A plan card standing in for one the store has not answered with yet.
struct PaywallPlanPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                skeleton(width: 54, height: 12)
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(GrokColor.white4, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                skeleton(width: 86, height: 20)
                skeleton(width: 110, height: 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PaywallMetrics.planHeight)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                .fill(GrokColor.white1)
        )
        .decorativeBorder(GrokColor.white4, cornerRadius: GrokMetrics.tileRadius)
    }

    private func skeleton(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(GrokColor.white4)
            .frame(width: width, height: height)
    }
}

// MARK: - Feature List

/// One line of the pitch: a tinted glyph tile, a name and an explanation.
struct PaywallFeatureRow: View {
    let feature: PaywallFeature

    var body: some View {
        HStack(spacing: 14) {
            feature.glyph
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: GrokMetrics.chipRadius, style: .continuous)
                        .fill(GrokColor.white4)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(feature.title)
                    .grokText(.paywallFeature, color: GrokColor.black1)
                Text(feature.detail)
                    .grokText(.paywallDetail, color: GrokColor.black6)
            }
        }
    }
}

/// What Pro unlocks. The three flows the app ships, in the sidebar's order.
struct PaywallFeature: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    /// Catalog assets are used where the app already ships one, so the dialog
    /// shows the same glyph the sidebar does.
    fileprivate let icon: Icon

    fileprivate enum Icon {
        case asset(String)
        case symbol(String)
    }

    @ViewBuilder
    fileprivate var glyph: some View {
        switch icon {
        case .asset(let name):
            GrokIcon(name, size: 22, color: GrokColor.black1)
        case .symbol(let name):
            SymbolIcon(name, size: 20, color: GrokColor.black1)
        }
    }

    static var all: [PaywallFeature] { [
        PaywallFeature(
            title: "feature.chat.title".localized,
            detail: "feature.chat.detail".localized,
            icon: .symbol("bubble.left.and.bubble.right")
        ),
        PaywallFeature(
            title: "feature.image.title".localized,
            detail: "feature.image.detail".localized,
            icon: .asset(GrokAsset.createImage)
        ),
        PaywallFeature(
            title: "feature.pdf.title".localized,
            detail: "feature.pdf.detail".localized,
            icon: .asset(GrokAsset.pdfSummary)
        )
    ] }
}

// MARK: - Preview Plate

/// The illustration beside the pitch: the app's own surfaces floating over the
/// sidebar's starfield, which is how the design shows what Pro unlocks.
struct PaywallPreviewPlate: View {

    var body: some View {
        ZStack(alignment: .topLeading) {
            SideBarBackground()

            askBar
                .offset(x: 28, y: 36)

            // The cards overlap, as the design file has them, but the document
            // card is placed past the end of the Create Image caption rather
            // than across it: it takes the image card's bottom-right corner,
            // which reads as a stack without costing the label underneath.
            imageCard
                .offset(x: 40, y: 104)

            documentCard
                .offset(x: 182, y: 244)
        }
        .frame(width: PaywallMetrics.previewWidth, height: PaywallMetrics.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: PaywallMetrics.previewRadius, style: .continuous))
    }

    /// The composer, reduced to its resting state.
    private var askBar: some View {
        HStack(spacing: 0) {
            Text("common.askAnything".localized)
                .grokText(.caption, color: GrokColor.black6)
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(GrokColor.black1)
                SymbolIcon("arrow.up", size: 16, weight: .semibold, color: GrokColor.white1)
            }
            .frame(width: 40, height: 40)
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(width: 260, height: 52)
        .background(Capsule().fill(Color.white.opacity(0.92)))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    /// A generated image, still in its card.
    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            imagePlaceholder

            HStack(spacing: 6) {
                GrokIcon(GrokAsset.createImage, size: 18, color: GrokColor.black1)
                Text("feature.image.title".localized)
                    .grokText(.paywallDetail, color: GrokColor.black1)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
        .padding(8)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                .fill(GrokColor.white1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 12)
    }

    /// The canvas before anything has been made, drawn the way the app draws
    /// its other upload target: a dashed well with the prompt along its foot.
    private var imagePlaceholder: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(GrokColor.white2)
                SymbolIcon("photo.badge.plus", size: 15, color: GrokColor.black5)
            }
            .frame(width: 34, height: 34)

            Text("paywall.uploadImage".localized)
                .grokText(.metadata, color: GrokColor.black5)
        }
        .frame(width: 204, height: 118)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(GrokColor.white4)
        )
        .decorativeBorder(GrokColor.white6, width: 1.5, cornerRadius: 14, dash: [5, 4])
    }

    /// A summarized document, its lines standing in for the summary.
    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GrokColor.white3)
                    GrokIcon(GrokAsset.pdfSummary, size: 18, color: GrokColor.black1)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(GrokColor.white4).frame(height: 5)
                    Capsule().fill(GrokColor.white4).frame(height: 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: 0.7, anchor: .leading)
                }
            }

            Text("feature.pdf.title".localized)
                .grokText(.paywallDetail, color: GrokColor.black1)
        }
        .padding(12)
        // A little narrower than the design's 168, which is what buys the
        // caption beside it room to finish inside the plate.
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.tileRadius, style: .continuous)
                .fill(GrokColor.white1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 12)
    }
}
