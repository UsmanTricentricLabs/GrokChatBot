//
//  PaywallView.swift
//  Grok
//
//  Created by Tricentric Labs on 08/10/2026.
//

import SwiftUI

/// The upgrade dialog.
///
/// The view owns nothing about subscriptions beyond which card is highlighted:
/// prices, trials, eligibility, purchasing and restoring all belong to
/// `IAPManager`, and the dialog only reads them back and reports taps. That is
/// why the button can promise a free trial — the manager has already asked the
/// App Store whether this account may still have one.
struct PaywallView: View {

    @ObservedObject var iap: IAPManager
    let onClose: () -> Void

    /// The highlighted card. `nil` until the store answers, because there is no
    /// valid product to select before then.
    @State private var selection: PremiumProductId?
    /// Set once the customer picks a card themselves, after which the default
    /// stops moving under them as late store data arrives.
    @State private var hasChosenManually = false
    @State private var isRestoring = false
    /// "Nothing to restore" — reported here rather than as an error, since
    /// `IAPManager` treats an empty restore as a normal outcome.
    @State private var restoreNote: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content

            closeButton
                .padding(20)
        }
        .frame(width: PaywallMetrics.dialogSize.width, height: PaywallMetrics.dialogSize.height)
        .background(
            RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous)
                .fill(GrokColor.white2)
        )
        .clipShape(RoundedRectangle(cornerRadius: GrokMetrics.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 40, x: 0, y: 30)
        .onAppear(perform: syncSelection)
        // Products and eligibility land separately — the store answers with the
        // products first and with this account's trial eligibility a moment
        // later — so the default is settled again after each.
        .onChange(of: iap.availablePlans) { _ in syncSelection() }
        .onChange(of: iap.introEligibility) { _ in syncSelection() }
    }

    // MARK: Layout

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .frame(height: PaywallMetrics.heroHeight)

            planGrid
                .padding(.top, 28)

            callToAction
                .padding(.top, 20)

            Spacer(minLength: 16)

            footer
        }
        .padding(.horizontal, PaywallMetrics.horizontalPadding)
        .padding(.top, PaywallMetrics.topPadding)
        .padding(.bottom, PaywallMetrics.bottomPadding)
    }

    /// The pitch beside the preview plate.
    private var hero: some View {
        HStack(alignment: .top, spacing: PaywallMetrics.heroSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("paywall.headline".localized)
                    .grokText(.paywallTitle, color: GrokColor.black1)
                    .fixedSize(horizontal: false, vertical: true)

                Text("paywall.subheadline".localized)
                    .grokText(.body, color: GrokColor.black6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380, alignment: .leading)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(PaywallFeature.all) { feature in
                        PaywallFeatureRow(feature: feature)
                    }
                }
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PaywallPreviewPlate()
        }
    }

    /// The three plans. Placeholders stand in until the store answers, so the
    /// dialog never shows a price it has not been given.
    private var planGrid: some View {
        HStack(spacing: PaywallMetrics.planSpacing) {
            if iap.hasLoadedPlans {
                ForEach(iap.availablePlans, id: \.self) { plan in
                    PaywallPlanCard(
                        plan: plan,
                        isSelected: selection == plan,
                        badge: PaywallBadge.forPlan(plan),
                        price: iap.displayPrice(for: plan) ?? "—",
                        period: iap.billingPeriodSuffix(for: plan).map { "/\($0)" } ?? "",
                        caption: iap.planCaption(for: plan),
                        isEnabled: !isBusy
                    ) {
                        select(plan)
                    }
                }
            } else {
                ForEach(IAPManager.planOrder, id: \.self) { _ in
                    PaywallPlanPlaceholder()
                }
            }
        }
    }

    private var callToAction: some View {
        VStack(spacing: 10) {
            Button(action: purchase) {
                HStack(spacing: 10) {
                    if iap.purchaseInProgress {
                        GrokSpinner(size: 18, color: GrokColor.white1)
                    }
                    Text(actionTitle)
                        .grokText(.paywallAction, color: GrokColor.white1)
                        .fixedSize()
                }
                .frame(width: PaywallMetrics.actionSize.width, height: PaywallMetrics.actionSize.height)
                .hoverBackground(
                    GrokColor.black1,
                    hover: GrokColor.black3,
                    cornerRadius: PaywallMetrics.actionSize.height / 2
                )
            }
            .buttonStyle(GrokButtonStyle())
            .disabled(selection == nil || isBusy)
            .opacity(selection == nil || isBusy ? 0.5 : 1)

            // The note keeps its line whether or not there is anything to say,
            // so the button does not shift as the message comes and goes.
            Text(note ?? " ")
                .grokText(.paywallDetail, color: isNoteAnError ? GrokColor.error : GrokColor.black6)
                .multilineTextAlignment(.center)
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Link("paywall.terms".localized, destination: SettingsDestination.terms)
                .grokText(.paywallFootnote, color: GrokColor.black5)

            divider

            Link("paywall.privacy".localized, destination: SettingsDestination.privacy)
                .grokText(.paywallFootnote, color: GrokColor.black5)

            divider

            Button(action: restore) {
                Text(isRestoring ? "paywall.restoring".localized : "paywall.restore".localized)
                    .grokText(.paywallFootnote, color: GrokColor.black5)
                    .fixedSize()
            }
            .buttonStyle(GrokButtonStyle())
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(GrokColor.white4)
            .frame(width: 1, height: 12)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            SymbolIcon("xmark", size: 13, weight: .medium, color: GrokColor.black1)
                .frame(width: 36, height: 36)
                .hoverBackground(GrokColor.white3, hover: GrokColor.white4, cornerRadius: 18)
        }
        .buttonStyle(GrokButtonStyle())
        .disabled(iap.purchaseInProgress)
        .help("common.close".localized)
    }

    // MARK: Copy

    /// The button's promise, and never more than the store will honour: a
    /// trial is only named when the selected plan actually carries one this
    /// account can still use.
    private var actionTitle: String {
        guard let selection, iap.hasFreeTrial(selection) else { return "paywall.cta.continue".localized }
        return "paywall.cta.freeTrial".localized
    }

    /// What the line under the button says. A failure outranks the billing
    /// terms, since it is the thing the customer needs to read.
    private var note: String? {
        if let errorMessage = iap.errorMessage { return errorMessage }
        if let restoreNote { return restoreNote }

        guard let selection else { return nil }

        return iap.trialSummary(for: selection) ?? iap.priceSummary(for: selection)
    }

    private var isNoteAnError: Bool {
        iap.errorMessage != nil || restoreNote != nil
    }

    private var isBusy: Bool {
        iap.purchaseInProgress || isRestoring
    }

    // MARK: Actions

    /// Settles which card opens highlighted.
    ///
    /// The choice itself belongs to `IAPManager`, which reads it off the
    /// products and this account's trial eligibility. A manual pick is left
    /// alone unless the plan behind it has gone away.
    private func syncSelection() {
        if hasChosenManually, let selection, iap.products[selection] != nil { return }

        selection = iap.defaultPlan
    }

    private func select(_ plan: PremiumProductId) {
        guard !isBusy else { return }

        selection = plan
        hasChosenManually = true
        clearNotes()
    }

    private func purchase() {
        guard let selection, !isBusy else { return }

        clearNotes()
        iap.purchase(selection)
    }

    /// Restores through the manager, which owns the entitlement check and the
    /// premium flag. The dialog only reports the "nothing found" case, which
    /// is not an error and so is not one the manager raises.
    private func restore() {
        guard !isBusy else { return }

        clearNotes()
        isRestoring = true

        iap.restorePurchases { restored in
            isRestoring = false

            if !restored {
                restoreNote = "paywall.noRestore".localized
            }
        }
    }

    private func clearNotes() {
        restoreNote = nil
        iap.errorMessage = nil
    }
}

// MARK: - Presentation

/// The dialog over its scrim, scaled down if the window is too small to show
/// it at the designed size.
struct PaywallOverlay: View {

    @ObservedObject var iap: IAPManager
    let containerSize: CGSize
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Ink alone, no material. A material over this light a canvas goes
            // milky and hides the app rather than setting it back, which is
            // all the scrim is for.
            GrokColor.black1.opacity(0.22)
                .ignoresSafeArea()
                // The scrim dismisses, except mid-purchase, when there is a
                // system sheet up and nothing good comes of closing underneath it.
                .onTapGesture {
                    guard !iap.purchaseInProgress else { return }
                    onClose()
                }

            PaywallView(iap: iap, onClose: onClose)
                .scaleEffect(scale)
        }
        .transition(
            .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
        )
    }

    /// The design draws the dialog at a fixed size, so a window smaller than
    /// that shrinks it whole rather than reflowing the layout.
    private var scale: CGFloat {
        guard containerSize.width > 0, containerSize.height > 0 else { return 1 }

        let margin: CGFloat = 40
        let horizontal = (containerSize.width - margin) / PaywallMetrics.dialogSize.width
        let vertical = (containerSize.height - margin) / PaywallMetrics.dialogSize.height

        return min(1, horizontal, vertical)
    }
}
