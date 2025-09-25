import WidgetKit
import SwiftUI
import Charts

struct EnergyEntry: TimelineEntry {
    let date: Date
    let samples: [SamplePoint]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyEntry {
        EnergyEntry(date: .now, samples: PowerCache.load())
    }
    func getSnapshot(in context: Context, completion: @escaping (EnergyEntry) -> ()) {
        completion(EnergyEntry(date: .now, samples: PowerCache.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyEntry>) -> ()) {
        let entry = EnergyEntry(date: .now, samples: PowerCache.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BatteryRing: View {
    let percent: Double
    let state: String

    private var clampedPercent: Double { max(0, min(percent, 100)) }
    private var progress: Double { clampedPercent / 100.0 }

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .foregroundStyle(progressColor)
                .rotationEffect(.degrees(-90))

            // Labels
            VStack(spacing: 2) {
                Text("\(Int(clampedPercent))%")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(state)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue("\(Int(clampedPercent)) percent, \(state)")
    }

    private var progressColor: Color {
        switch clampedPercent {
        case ..<15: return .red
        case ..<40: return .orange
        default: return .green
        }
    }
}

struct EnergyWidgetView: View {
    let e: EnergyEntry
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                BatteryRing(percent: e.samples.last?.soc ?? 0,
                            state: batteryState(e.samples.last))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Solar \(Fmt.wattString(e.samples.last?.solar ?? 0))").font(.caption).monospacedDigit()
                    Text("Home  \(Fmt.wattString(e.samples.last?.home  ?? 0))").font(.caption).monospacedDigit()
                    Text("Grid  \(Fmt.wattString(e.samples.last?.grid  ?? 0))").font(.caption).monospacedDigit()
                }
            }
            Chart(e.samples) {
                LineMark(x: .value("Time", $0.t), y: .value("Solar", $0.solar))
                LineMark(x: .value("Time", $0.t), y: .value("Home",  $0.home))
                RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3,3]))
                LineMark(x: .value("Time", $0.t), y: .value("Grid", $0.grid))
            }
        }.padding(10)
    }
    func batteryState(_ last: SamplePoint?) -> String {
        guard let last = last else { return "—" }
        if last.battery > 0 { return "Discharging" }
        if last.battery < 0 { return "Charging" }
        return "Idle"
    }
}

struct EnergyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EnergyWidget", provider: Provider()) { entry in
            EnergyWidgetView(e: entry)
        }
        .configurationDisplayName("Home Energy")
        .description("Solar, battery, grid and home power")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
