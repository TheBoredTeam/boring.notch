//
//  StatsView.swift
//  boringNotch
//
//  Adapted from DynamicIsland NotchStatsView
//  Stats tab view for system performance monitoring
//

import SwiftUI
import Defaults

// Graph data protocol for unified interface
protocol GraphData {
    var title: String { get }
    var color: Color { get }
    var icon: String { get }
    var type: GraphType { get }
}

enum GraphType {
    case single
    case dual
}

// Single value graph data
struct SingleGraphData: GraphData {
    let title: String
    let value: String
    let data: [Double]
    let color: Color
    let icon: String
    let type: GraphType = .single
}

struct StatsView: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    
    var availableGraphs: [GraphData] {
        var graphs: [GraphData] = []
        
        // Only CPU, Memory, and GPU as requested
        graphs.append(SingleGraphData(
            title: "CPU",
            value: statsManager.cpuUsageString,
            data: statsManager.cpuHistory,
            color: .blue,
            icon: "cpu"
        ))
        
        graphs.append(SingleGraphData(
            title: "Memory",
            value: statsManager.memoryUsageString,
            data: statsManager.memoryHistory,
            color: .green,
            icon: "memorychip"
        ))
        
        graphs.append(SingleGraphData(
            title: "GPU",
            value: statsManager.gpuUsageString,
            data: statsManager.gpuHistory,
            color: .purple,
            icon: "display"
        ))
        
        return graphs
    }
    
    // Smart grid layout system for 3 graphs
    @ViewBuilder
    var statsGridLayout: some View {
        // 3 graphs: Single row with equal spacing
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 12
        ) {
            ForEach(0..<availableGraphs.count, id: \.self) { index in
                UnifiedStatsCard(graphData: availableGraphs[index])
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.4)),
                        removal: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.4))
                    ))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !enableStatsFeature {
                // Disabled state
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Stats Disabled")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Enable stats monitoring in Settings to view system performance data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Stats content - simplified layout without controls
                VStack(spacing: 12) {
                    statsGridLayout
                }
                .padding(16)
                .animation(.easeInOut(duration: 0.4), value: availableGraphs.count)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.4)),
                    removal: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.4))
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if enableStatsFeature && Defaults[.autoStartStatsMonitoring] && !statsManager.isMonitoring {
                statsManager.startMonitoring()
            }
        }
        .onDisappear {
            // Keep monitoring running when tab is not visible
        }
        .animation(.easeInOut(duration: 0.4), value: enableStatsFeature)
        .animation(.easeInOut(duration: 0.4), value: availableGraphs.count)
    }
}

// Unified Stats Card Component - handles single data type only (no dual for boring notch)
struct UnifiedStatsCard: View {
    let graphData: GraphData
    
    var body: some View {
        VStack(spacing: 6) {
            // Header - consistent across all card types
            HStack(spacing: 4) {
                Image(systemName: graphData.icon)
                    .foregroundColor(graphData.color)
                    .font(.caption2)
                
                Text(graphData.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Values section - single data only
            Group {
                if let singleData = graphData as? SingleGraphData {
                    Text(singleData.value)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
            .frame(height: 22) // Fixed height for consistent card sizing
            
            // Graph section - single data only
            Group {
                if let singleData = graphData as? SingleGraphData {
                    MiniGraph(data: singleData.data, color: singleData.color)
                }
            }
            .frame(height: 50) // Fixed height for consistent card sizing
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MiniGraph: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxValue = data.max() ?? 1.0
            let normalizedData = maxValue > 0 ? data.map { $0 / maxValue } : data
            
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                for (index, value) in normalizedData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat(value))
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 2)
            
            // Gradient fill
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                
                for (index, value) in normalizedData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat(value))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

#Preview {
    StatsView()
        .frame(width: 400, height: 300)
        .background(Color.black)
}
