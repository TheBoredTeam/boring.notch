//
//  BoringReminders.swift
//  boringNotch
//
//  Created by Andrew Zhao on 4/24/25.
//

import SwiftUI
import EventKit

struct BoringRemindersView: View {
    @StateObject private var reminderManager = ReminderManager()

    private static let wheelPickerHeight: CGFloat = 50

    var body: some View {
        VStack(spacing: 8) {

            // ───── header ─────
            HStack {
                Text("Reminders")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom , 9)
            }

            switch reminderManager.authorizationStatus {
            case .notDetermined:
                Text("Requesting access to reminders...")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)

            case .denied, .restricted:
                Text("Reminder access denied or restricted.")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .center)

            case .authorized, .fullAccess, .writeOnly:
                GeometryReader { geo in                      // ← always present
                    Group {
                        if reminderManager.reminders.isEmpty {
                            Text("No upcoming reminders")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity,   // use all the space
                                       maxHeight: .infinity,
                                       alignment: .center)
                        } else {
                            ScrollView(showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(reminderManager.reminders,
                                            id: \.calendarItemIdentifier) { reminder in
                                        ReminderRow(reminder: reminder) {
                                            reminderManager.toggleCompletion(for: reminder)
                                        }
                                        .frame(maxWidth: .infinity,
                                               alignment: .leading)
                                    }
                                }
                                .padding(.top, 1)
                                .padding(.horizontal, 1)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                }

            @unknown default:
                Text("Unknown reminder permission status")
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // grow to full height like the calendar column …
        .frame(maxHeight: .infinity, alignment: .top)
        .offset(y: 8)
        .padding(.bottom, 8)
        .scrollIndicators(.never)
        .scrollTargetBehavior(.viewAligned)
    }
}

struct ReminderRow: View {
    let reminder: EKReminder
    var onTap: () -> Void
    @State private var isCompleted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .gray)
                .font(.footnote)
                .padding(.top, 2)
                .animation(.easeInOut(duration: 0.2), value: isCompleted)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.footnote)
                    .foregroundColor(.gray)
                if let date = reminder.dueDateComponents?.date {
                    Text(date, style: .date)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isCompleted.toggle()
            withAnimation {
                onTap()
            }
        }
        .onAppear {
            isCompleted = reminder.isCompleted // set initial state
        }
    }
}

#Preview {
    BoringRemindersView()
        .frame(width: 250)
        .padding()
        .background(.black)
}
