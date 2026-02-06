import SwiftUI
import Foundation

struct PanelComputedStatus {
    enum Bucket {
        case absent
        case overposted      // ✅ NEW
        case todo
        case upToDate        // <24h
        case old             // >=24h
        case pendingSync
    }

    let local: PanelLocalStatus?

    var isAbsent: Bool { local?.isAbsent == true }
    var isOverposted: Bool { local?.isOverposted == true }   // ✅ NEW

    var bucket: Bucket {
        // ⚠️ ordre important
        if local?.needsSync == true { return .pendingSync }
        if local?.isAbsent == true { return .absent }
        if local?.isOverposted == true { return .overposted } // ✅ NEW

        guard let d = local?.lastCoveredAt else { return .todo }

        let age = Date().timeIntervalSince(d)
        if age < 24 * 60 * 60 { return .upToDate }
        return .old
    }

    var whenText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        // ✅ absent
        if isAbsent, let d = local?.absentAt {
            return formatter.string(from: d)
        }

        // ✅ recouvert adversaires
        if isOverposted, let d = local?.overpostedAt {
            return formatter.string(from: d)
        }

        // ✅ fait
        if let d = local?.lastCoveredAt {
            return formatter.string(from: d)
        }

        return "—"
    }
}

struct PanelPin: View {
    let status: PanelComputedStatus

    var body: some View {
        switch status.bucket {
        case .absent:
            Circle()
                .fill(Color.black)
                .opacity(0.25)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                )

        case .overposted:
            // 🔵 bleu + icône pour distinguer du “pendingSync”
            Circle()
                .fill(Color.blue)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                )

        case .todo:
            pin(color: .red)

        case .upToDate:
            pin(color: .green)

        case .old:
            pin(color: .orange)

        case .pendingSync:
            // 🟦 on garde bleu mais avec style différent (pour pas confondre)
            Circle()
                .fill(Color.cyan)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }

    private func pin(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

struct PanelDot: View {
    let status: PanelComputedStatus

    var body: some View {
        let color: Color = {
            switch status.bucket {
            case .absent: return .black.opacity(0.25)
            case .overposted: return .blue
            case .todo: return .red
            case .upToDate: return .green
            case .old: return .orange
            case .pendingSync: return .cyan
            }
        }()

        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
    }
}
