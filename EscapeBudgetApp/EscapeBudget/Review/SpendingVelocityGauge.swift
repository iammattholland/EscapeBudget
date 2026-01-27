import SwiftUI

/// A semicircular gauge for displaying spending velocity with colored zones
struct SpendingVelocityGauge: View {
    /// Velocity ratio (1.0 = on pace). Values > 2.0 are clamped for display.
    let velocityRatio: Double
    /// Diameter of the gauge
    let size: CGFloat

    @Environment(\.appColorMode) private var appColorMode

    // MARK: - Configuration

    private let trackLineWidth: CGFloat = 8

    // Zone boundaries (velocity ratios)
    private let greenZoneEnd: Double = 0.85
    private let yellowZoneEnd: Double = 1.15

    // MARK: - Computed

    /// Clamped ratio for display (0 to 2)
    private var displayRatio: Double {
        max(0, min(2, velocityRatio))
    }

    /// Progress through the gauge (0 to 1)
    private var progress: Double {
        displayRatio / 2.0
    }

    // MARK: - Colors

    private var greenColor: Color {
        AppColors.success(for: appColorMode)
    }

    private var yellowColor: Color {
        AppColors.warning(for: appColorMode)
    }

    private var redColor: Color {
        AppColors.danger(for: appColorMode)
    }

    private var trackColor: Color {
        Color(.systemGray5)
    }

    /// Color based on current velocity zone
    private var indicatorColor: Color {
        switch velocityRatio {
        case ..<greenZoneEnd:
            return greenColor
        case greenZoneEnd..<yellowZoneEnd:
            return yellowColor
        default:
            return redColor
        }
    }

    // MARK: - Body

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height - 2)
            let radius = min(canvasSize.width, canvasSize.height * 2) / 2 - trackLineWidth / 2 - 2

            // Draw background track (faded)
            drawArc(
                context: context,
                center: center,
                radius: radius,
                startDegrees: 180,
                endDegrees: 0,
                color: trackColor,
                lineWidth: trackLineWidth
            )

            // Draw colored zone segments (faded as background reference)
            let greenEndDegrees = 180 - (greenZoneEnd / 2.0 * 180)
            let yellowEndDegrees = 180 - (yellowZoneEnd / 2.0 * 180)

            drawArc(
                context: context,
                center: center,
                radius: radius,
                startDegrees: 180,
                endDegrees: greenEndDegrees,
                color: greenColor.opacity(0.3),
                lineWidth: trackLineWidth
            )

            drawArc(
                context: context,
                center: center,
                radius: radius,
                startDegrees: greenEndDegrees,
                endDegrees: yellowEndDegrees,
                color: yellowColor.opacity(0.3),
                lineWidth: trackLineWidth
            )

            drawArc(
                context: context,
                center: center,
                radius: radius,
                startDegrees: yellowEndDegrees,
                endDegrees: 0,
                color: redColor.opacity(0.3),
                lineWidth: trackLineWidth
            )

            // Draw progress arc (filled portion showing current velocity)
            let currentAngle = 180 - (progress * 180)
            if progress > 0 {
                drawArc(
                    context: context,
                    center: center,
                    radius: radius,
                    startDegrees: 180,
                    endDegrees: currentAngle,
                    color: indicatorColor,
                    lineWidth: trackLineWidth
                )
            }
        }
        .frame(width: size, height: size / 2 + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(String(format: "%.0f percent of budget pace", velocityRatio * 100))
    }

    // MARK: - Drawing Helpers

    private func drawArc(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        startDegrees: Double,
        endDegrees: Double,
        color: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: true
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        switch velocityRatio {
        case ..<greenZoneEnd:
            return "Spending pace gauge showing under budget pace"
        case greenZoneEnd..<yellowZoneEnd:
            return "Spending pace gauge showing on track"
        default:
            return "Spending pace gauge showing over budget pace"
        }
    }
}

// MARK: - Previews

#Preview("On Pace") {
    VStack(spacing: 20) {
        SpendingVelocityGauge(velocityRatio: 1.0, size: 80)
        Text("1.0x - On Pace")
    }
    .padding()
}

#Preview("Under Pace") {
    VStack(spacing: 20) {
        SpendingVelocityGauge(velocityRatio: 0.5, size: 80)
        Text("0.5x - Under Pace")
    }
    .padding()
}

#Preview("Over Pace") {
    VStack(spacing: 20) {
        SpendingVelocityGauge(velocityRatio: 1.5, size: 80)
        Text("1.5x - Over Pace")
    }
    .padding()
}

#Preview("All States") {
    HStack(spacing: 30) {
        VStack {
            SpendingVelocityGauge(velocityRatio: 0.3, size: 60)
            Text("0.3x").font(.caption)
        }
        VStack {
            SpendingVelocityGauge(velocityRatio: 0.85, size: 60)
            Text("0.85x").font(.caption)
        }
        VStack {
            SpendingVelocityGauge(velocityRatio: 1.0, size: 60)
            Text("1.0x").font(.caption)
        }
        VStack {
            SpendingVelocityGauge(velocityRatio: 1.15, size: 60)
            Text("1.15x").font(.caption)
        }
        VStack {
            SpendingVelocityGauge(velocityRatio: 1.8, size: 60)
            Text("1.8x").font(.caption)
        }
    }
    .padding()
}
