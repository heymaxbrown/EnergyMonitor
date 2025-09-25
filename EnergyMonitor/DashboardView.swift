import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @State private var samples: [SamplePoint] = PowerCache.load()
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Home Energy").font(.title2).bold()
            Chart(samples) {
                LineMark(x: .value("Time", $0.t), y: .value("Solar", $0.solar))
                LineMark(x: .value("Time", $0.t), y: .value("Home",  $0.home))
                LineMark(x: .value("Time", $0.t), y: .value("Battery", $0.battery))
                RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3,3]))
                LineMark(x: .value("Time", $0.t), y: .value("Grid", $0.grid))
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 260)

            HStack(spacing: 20) {
                StatRow(icon: "sun.max.fill", label: "Solar",  value: Fmt.wattString(samples.last?.solar ?? 0))
                StatRow(icon: "house.fill",   label: "Home",   value: Fmt.wattString(samples.last?.home  ?? 0))
                StatRow(icon: "bolt.horizontal.fill", label: "Grid", value: Fmt.wattString(samples.last?.grid ?? 0))
                StatRow(icon: "battery.100",  label: "Battery", value: Fmt.wattString(samples.last?.battery ?? 0))
            }
            Spacer()
        }
        .padding(16)
        .onReceive(timer) { _ in samples = PowerCache.load() }
    }
}//
//  DashboardView.swift
//  EnergyMonitor
//
//  Created by Max Brown on 9/24/25.
//


