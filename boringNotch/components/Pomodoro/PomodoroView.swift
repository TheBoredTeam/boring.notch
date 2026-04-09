import SwiftUI

struct PomodoroView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    @State private var isEditing: Bool = false
    
    @State private var editMinutes: Int = 25
    @State private var editSeconds: Int = 0

    @State private var isHovering: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            // MARK: - Left: Session Types
            VStack(alignment: .leading, spacing: 12) {
                sessionButton(title: "Focus", type: .work)
                sessionButton(title: "Short Break", type: .shortBreak)
                sessionButton(title: "Long Break", type: .longBreak)
            }
            .disabled(isEditing)
            .opacity(isEditing ? 0.3 : 1.0)
            
            // MARK: - Center: Timer
            ZStack {
                if isEditing {
                    HStack(spacing: 4) {
                        Picker("", selection: $editMinutes) {
                            ForEach(0...90, id: \.self) { min in
                                Text(String(format: "%02d", min)).tag(min)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 50)
                        
                        Text(":")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.bottom, 2)
                        
                        Picker("", selection: $editSeconds) {
                            ForEach(0...59, id: \.self) { sec in
                                Text(String(format: "%02d", sec)).tag(sec)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text(pomodoroManager.formattedTime)
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .contentShape(Rectangle()) 
                        .scaleEffect(isHovering ? 1.04 : 1.0)
                        .onHover { hover in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isHovering = hover
                            }
                        }
                        .onTapGesture {
                            if pomodoroManager.state != .running {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    editMinutes = Int(pomodoroManager.timeRemaining) / 60
                                    editSeconds = Int(pomodoroManager.timeRemaining) % 60
                                    isEditing = true
                                }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: 160, height: 70) 
            
            // MARK: - Right: Controls
            HStack(spacing: 16) {
                if isEditing {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            pomodoroManager.setCustomTime(minutes: editMinutes, seconds: editSeconds)
                            isEditing = false
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isEditing = false
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: .secondarySystemFill)) 
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                    
                } else {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if pomodoroManager.state == .running {
                                pomodoroManager.pause()
                            } else {
                                pomodoroManager.start()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 48, height: 48) 
                            Image(systemName: pomodoroManager.state == .running ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            pomodoroManager.resetTimer()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: .secondarySystemFill)) 
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 100)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private func sessionButton(title: String, type: PomodoroManager.SessionType) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                pomodoroManager.setSession(type)
            }
        }) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .frame(width: 95, alignment: .leading)
                .background(pomodoroManager.currentSession == type ? Color(nsColor: .secondarySystemFill) : Color.clear)
                .foregroundColor(pomodoroManager.currentSession == type ? .white : .gray)
                .clipShape(Capsule()) 
        }
        .buttonStyle(PlainButtonStyle())
    }
}
