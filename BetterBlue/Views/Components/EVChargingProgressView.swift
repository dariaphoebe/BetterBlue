//
//  EVChargingProgressView.swift
//  BetterBlue
//
//  Shared view for EV charging progress display
//  Used by both EVRangeChargingCard and Live Activity
//

import SwiftUI

/// Shared view for displaying EV charging progress
/// Used by EVRangeChargingCard in the main app and VehicleActivityWidget for Live Activities
struct EVChargingProgressView: View {
    let icon: Image?
    let formattedRange: String
    let batteryPercentage: Int
    let isCharging: Bool
    let chargeSpeed: String?
    let chargeTimeRemaining: String?
    let targetSOC: Double?
    let showHeader: Bool
    /// Tint used for the actively-charging progress fill and the pulsing
    /// header icon. Callers pass the vehicle's customizable
    /// `chargingColor` so the bar matches the rest of the app's accents.
    let chargingColor: Color

    init(
        icon: Image? = nil,
        formattedRange: String = "",
        batteryPercentage: Int,
        isCharging: Bool,
        chargeSpeed: String?,
        chargeTimeRemaining: String?,
        targetSOC: Double?,
        showHeader: Bool = true,
        chargingColor: Color = .green
    ) {
        self.icon = icon
        self.formattedRange = formattedRange
        self.batteryPercentage = batteryPercentage
        self.isCharging = isCharging
        self.chargeSpeed = chargeSpeed
        self.chargeTimeRemaining = chargeTimeRemaining
        self.targetSOC = targetSOC
        self.showHeader = showHeader
        self.chargingColor = chargingColor
    }

    var body: some View {
        VStack(spacing: 12) {
            if showHeader {
                // Top row: Icon (optional), Range, and Battery percentage
                HStack(spacing: 12) {
                    if let icon {
                        icon
                            .font(.title2)
                            .foregroundColor(isCharging ? chargingColor : .primary)
                            .symbolEffect(.pulse, isActive: isCharging)
                            .frame(width: 28)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("EV Range")
                            .font(.caption)
                        Text(formattedRange)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Battery")
                            .font(.caption)
                        Text("\(batteryPercentage)%")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.primary)
            }

            // Progress bar
            if isCharging {
                chargingProgressBar
            } else {
                notChargingProgressBar
            }
        }
    }

    private var chargingProgressBar: some View {
        VStack(spacing: 4) {
            // Capsule track with a rectangular fill masked to it (flat
            // trailing edge), and a thin charge-limit line tinted to match
            // the limit pill below.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 32)

                        Rectangle()
                            .fill(chargingColor)
                            .frame(width: fillWidth(geometry.size.width), height: 32)

                        if let targetSOC, targetSOC < 100 {
                            ChargeLimitLine()
                                .stroke(Color.secondary, lineWidth: 1.5)
                                .frame(width: 1.5, height: 32)
                                .offset(x: geometry.size.width * (targetSOC / 100.0) - 0.75)
                        }
                    }
                    .clipShape(Capsule())

                    // Time remaining (left), charge speed (right) — same
                    // fill-aware placement as the widget so each label sits
                    // over the green fill or the gray remainder rather than
                    // straddling the boundary.
                    if let timeRemaining = chargeTimeRemaining {
                        Text(timeRemaining)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .padding(.leading, 12)
                            .offset(x: fillFraction > 0.25 ? 0 : fillWidth(geometry.size.width))
                    }

                    if let speed = chargeSpeed {
                        Text(speed)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .padding(.trailing, 12)
                            .frame(
                                width: fillFraction < 0.8 ? geometry.size.width : fillWidth(geometry.size.width),
                                alignment: .trailing
                            )
                    }
                }
            }
            .frame(height: 32)

            // Numeric charge-limit pill, centered under the line at the
            // limit. Unlike the widget, the larger surfaces have room for
            // the explicit "<n>%" target. Hidden at 100%.
            if let targetSOC, targetSOC < 100 {
                GeometryReader { geometry in
                    Text("\(Int(targetSOC))% limit")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                        .position(
                            x: clampedPillX(geometry.size.width, target: targetSOC),
                            y: 11
                        )
                }
                .frame(height: 22)
            }
        }
    }

    /// Keep the limit pill inside the bar's width so it doesn't clip at
    /// high targets, leaving roughly half a small pill's width of margin.
    private func clampedPillX(_ width: CGFloat, target: Double) -> CGFloat {
        let x = width * (target / 100.0)
        let margin: CGFloat = 22
        return min(max(x, margin), width - margin)
    }

    /// Battery fill as a 0...1 fraction and its pixel width — used to
    /// keep the inline labels off the fill/gray boundary.
    private var fillFraction: Double { min(max(Double(batteryPercentage) / 100.0, 0), 1) }
    private func fillWidth(_ width: CGFloat) -> CGFloat { width * fillFraction }

    private var notChargingProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)

                // Foreground
                Capsule()
                    .fill(Color.gray.opacity(0.5))
                    .frame(
                        width: geometry.size.width * (Double(batteryPercentage) / 100.0),
                        height: 6
                    )
            }
        }
        .frame(height: 6)
    }
}
