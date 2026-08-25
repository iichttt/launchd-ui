import LaunchdCore
import SwiftUI

/// Relative time for the "Last Run" column, matching the thresholds JobRow.tsx used.
func formatRelativeTime(_ epochMillis: Double) -> String {
    let diff = Date().timeIntervalSince1970 - epochMillis / 1000
    let seconds = Int(diff)
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 30 { return "\(days)d ago" }
    let date = Date(timeIntervalSince1970: epochMillis / 1000)
    let parts = Calendar.current.dateComponents([.month, .day], from: date)
    return "\(parts.month ?? 0)/\(parts.day ?? 0)"
}

private struct BadgeLabel: View {
    var text: String
    var color: Color
    var filled: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(filled ? .white : color)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(filled ? color : .clear)
                    .strokeBorder(filled ? .clear : color.opacity(0.5))
            }
    }
}

struct StatusBadge: View {
    var status: JobStatus

    var body: some View {
        switch status {
        case .running: BadgeLabel(text: "Running", color: .green, filled: true)
        case .loaded: BadgeLabel(text: "Loaded", color: .blue, filled: true)
        case .unloaded: BadgeLabel(text: "Unloaded", color: .secondary, filled: false)
        case .unknown: BadgeLabel(text: "Unknown", color: .secondary, filled: false)
        }
    }
}

struct SourceBadge: View {
    var source: JobSource

    var body: some View {
        switch source {
        case .userAgent: BadgeLabel(text: "User", color: .secondary, filled: false)
        case .systemAgent: BadgeLabel(text: "System", color: .blue, filled: false)
        case .systemDaemon: BadgeLabel(text: "Daemon", color: .purple, filled: false)
        }
    }
}
