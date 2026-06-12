//
//  VehicleWidgetView.swift
//  BetterBlueWidget
//
//  Created by Mark Schmidt on 8/29/25.
//

import AppIntents
import BetterBlueKit
import SwiftUI
import WidgetKit

struct VehicleWidgetEntryView: View {
    let entry: VehicleWidgetEntry

    var body: some View {
        if let vehicle = entry.vehicle {
            VehicleControlsWidget(vehicle: vehicle, actions: entry.configuration.slotActions)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        gradient: Gradient(colors: vehicle.backgroundGradient),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else {
            VStack {
                Image(systemName: "car.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No Vehicle")
                    .font(.headline)
                Text("Add an account in the app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
    }
}

struct VehicleControlsWidget: View {
    let vehicle: VehicleEntity
    let actions: [WidgetActionEntity]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Link(destination: URL(string: "betterblue://vehicle/\(vehicle.vin)")!) {
            switch family {
            case .systemSmall:
                VehicleSmallWidget(vehicle: vehicle, actions: actions)
            default:
                VehicleMediumWidget(vehicle: vehicle, actions: actions)
            }
        }
    }
}

struct VehicleMediumWidget: View {
    let vehicle: VehicleEntity
    let actions: [WidgetActionEntity]

    var body: some View {
        UnifiedVehicleWidget(vehicle: vehicle, actions: actions, isSmall: false)
    }
}

struct WidgetButtonStyle: ButtonStyle {
    let backgroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundColor.opacity(0.6))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct VehicleSmallWidget: View {
    let vehicle: VehicleEntity
    let actions: [WidgetActionEntity]

    var body: some View {
        UnifiedVehicleWidget(vehicle: vehicle, actions: actions, isSmall: true)
    }
}

// Unified widget components
struct UnifiedVehicleWidget: View {
    let vehicle: VehicleEntity
    let actions: [WidgetActionEntity]
    let isSmall: Bool

    var body: some View {
        VStack(spacing: isSmall ? 0 : 8) {
            // Vehicle header
            VehicleHeaderView(vehicle: vehicle, isSmall: isSmall)

            // Action buttons
            VehicleButtonsView(vehicle: vehicle, actions: actions, isSmall: isSmall)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, isSmall ? 0 : 16)
    }
}

struct VehicleHeaderView: View {
    let vehicle: VehicleEntity
    let isSmall: Bool

    private var textColor: Color {
        let backgroundColors = vehicle.backgroundGradient
        guard !backgroundColors.isEmpty else { return .primary }

        let primaryColor = backgroundColors[0]
        return isLightColor(primaryColor) ? .black : .white
    }

    private func isLightColor(_ color: Color) -> Bool {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Calculate perceived brightness using standard luminance formula
        let brightness = (red * 0.299) + (green * 0.587) + (blue * 0.114)
        return brightness > 0.5
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(vehicle.displayName)
                    .font(isSmall ? .caption : .headline)
                    .fontWeight(.bold)
                    .foregroundColor(textColor)
                    .lineLimit(1)

                Text(updatedText)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            if isSmall {
                if vehicle.displayName.count <= 9 {
                    // Small widget: only show range if name is 8 characters or less
                    Text(vehicle.rangeText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }
            } else {
                // Medium widget: icon, range, dot, percentage
                HStack(spacing: 4) {
                    Image(systemName: vehicle.fuelType.hasElectricCapability ? "bolt.fill" : "fuelpump.fill")
                        .foregroundColor(vehicle.fuelType.hasElectricCapability ? vehicle.chargingColor : .orange)
                        .font(.caption)

                    Text(vehicle.rangeText)
                        .font(.caption)
                        .foregroundColor(textColor)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.7))

                    if let percentage = vehicle.batteryPercentage {
                        Text("\(Int(percentage))%")
                            .font(.caption)
                            .foregroundColor(textColor)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isSmall ? 4 : 6)
        .cornerRadius(12)
        .padding(.bottom, isSmall ? 4 : 0)
    }

    private var updatedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: vehicle.timestamp, relativeTo: Date())
    }
}

extension WidgetActionEntity {
    /// Maps a configured action onto its concrete control intent,
    /// targeting the widget's vehicle (or, for a preset-specific
    /// action, the preset's own vehicle). Lives here — not next to the
    /// entity — because the control intents are iOS-only while the
    /// entity is shared with the watch widget target.
    func makeIntent(for vehicle: VehicleEntity) -> (any AppIntent)? {
        switch kind {
        case .lock:
            let intent = LockVehicleControlIntent()
            intent.vehicle = vehicle
            return intent
        case .unlock:
            let intent = UnlockVehicleControlIntent()
            intent.vehicle = vehicle
            return intent
        case .stopClimate:
            let intent = StopClimateControlIntent()
            intent.vehicle = vehicle
            return intent
        case .startCharge:
            let intent = StartChargeControlIntent()
            intent.vehicle = vehicle
            return intent
        case .stopCharge:
            let intent = StopChargeControlIntent()
            intent.vehicle = vehicle
            return intent
        case .startClimate:
            let intent = StartClimateControlIntent()
            if let presetId, let presetVin {
                intent.preset = ClimatePresetEntity(
                    id: presetId,
                    vehicleVin: presetVin,
                    vehicleName: presetVehicleName ?? vehicle.displayName,
                    presetName: presetName ?? "Climate",
                    presetIcon: presetIcon ?? "fan",
                    isSelected: false
                )
            } else {
                intent.preset = vehicle.selectedPreset
            }
            return intent
        case .none:
            return nil
        }
    }

    /// Icon to render on the button. A preset-specific start-climate
    /// action carries the preset's own icon; the generic "Start
    /// Climate" resolves to the vehicle's selected-preset icon so the
    /// button matches what it'll actually run.
    func displayIcon(for vehicle: VehicleEntity) -> String {
        if kind == .startClimate, presetId == nil {
            return vehicle.selectedPreset?.presetIcon ?? iconName
        }
        return iconName
    }
}

struct VehicleButtonsView: View {
    let vehicle: VehicleEntity
    let actions: [WidgetActionEntity]
    let isSmall: Bool

    var body: some View {
        if isSmall {
            // Small widget: 2-column grid, icons only
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 4), count: 2), spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    actionButton(action)
                }
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .fontWeight(.medium)
        } else {
            // Medium widget: rows of two with full labels
            VStack(spacing: 8) {
                ForEach(Array(actions.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, action in
                            actionButton(action)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .font(.caption)
            .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: WidgetActionEntity) -> some View {
        if let intent = action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                Label(action.kind.defaultTitle, systemImage: action.displayIcon(for: vehicle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(WidgetButtonStyle(backgroundColor: action.kind.color(for: vehicle)))
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

#Preview(as: .systemMedium) {
    BetterBlueWidget()
} timeline: {
    let placeholderVehicle = VehicleEntity(
        id: .init(),
        displayName: "Ioniq 5",
        vin: "test",
        fuelType: .electric,
        rangeText: "250 mi",
        batteryPercentage: 85.0,
        timestamp: Date(),
        backgroundColorName: "white",
    )

    VehicleWidgetEntry(date: .now, vehicle: placeholderVehicle, configuration: VehicleWidgetIntent())
}

#Preview(as: .systemSmall) {
    BetterBlueWidget()
} timeline: {
    let placeholderVehicle = VehicleEntity(
        id: .init(),
        displayName: "Genesis GV60",
        vin: "test",
        fuelType: .electric,
        rangeText: "250 mi",
        batteryPercentage: 85.0,
        timestamp: Date(),
        backgroundColorName: "white",
    )

    VehicleWidgetEntry(date: .now, vehicle: placeholderVehicle, configuration: VehicleWidgetIntent())
}

struct LockScreenVehicleWidgetView: View {
    let entry: VehicleWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let vehicle = entry.vehicle {
            switch family {
            case .accessoryCircular:
                LockScreenRangeWidget(vehicle: vehicle)
                    .containerBackground(for: .widget) {
                        Color.clear
                    }
            case .accessoryRectangular:
                LockScreenWideRangeWidget(vehicle: vehicle)
                    .containerBackground(for: .widget) {
                        Color.clear
                    }
            default:
                LockScreenRangeWidget(vehicle: vehicle)
                    .containerBackground(for: .widget) {
                        Color.clear
                    }
            }
        } else {
            Image(systemName: "car.fill")
                .foregroundColor(.secondary)
                .font(.title2)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
    }
}

struct LockScreenProgressIcon: View {
    let vehicle: VehicleEntity
    let lineWidth = 3.0

    private var rangePercentage: Double {
        guard let batteryPercentage = vehicle.batteryPercentage else { return 0.0 }
        return batteryPercentage / 100.0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: rangePercentage)
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1), value: rangePercentage)

            Image(systemName: vehicle.fuelType.hasElectricCapability ? "bolt.car.fill" : "car.fill")
        }
        .frame(width: 44, height: 44)
    }
}

struct LockScreenRangeWidget: View {
    let vehicle: VehicleEntity

    var body: some View {
        LockScreenProgressIcon(
            vehicle: vehicle,
        )
    }
}

struct LockScreenWideRangeWidget: View {
    let vehicle: VehicleEntity

    var body: some View {
        HStack(spacing: 8) {
            // Progress icon on the left
            LockScreenProgressIcon(
                vehicle: vehicle,
            )

            // Vehicle name and range text
            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(vehicle.rangeText)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .accessoryCircular) {
    BetterBlueLockScreenWidget()
} timeline: {
    let placeholderVehicle = VehicleEntity(
        id: .init(),
        displayName: "Model Y",
        vin: "test",
        fuelType: .electric,
        rangeText: "280 mi",
        batteryPercentage: 75.0,
        timestamp: Date(),
        backgroundColorName: "white"
    )

    VehicleWidgetEntry(date: .now, vehicle: placeholderVehicle, configuration: VehicleWidgetIntent())
}

#Preview(as: .accessoryRectangular) {
    BetterBlueLockScreenWidget()
} timeline: {
    let placeholderVehicle = VehicleEntity(
        id: .init(),
        displayName: "Ioniq 5",
        vin: "test",
        fuelType: .electric,
        rangeText: "250 mi",
        batteryPercentage: 85.0,
        timestamp: Date(),
        backgroundColorName: "white"
    )

    VehicleWidgetEntry(date: .now, vehicle: placeholderVehicle, configuration: VehicleWidgetIntent())
}
