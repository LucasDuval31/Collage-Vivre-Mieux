//
//  ExtraPanelPin.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 23/12/2025.
//

import SwiftUI

struct ExtraPanelPin: View {
    let status: PanelComputedStatus

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color(for: status))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                )

            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .opacity(status.bucket == .absent ? 0.35 : 1.0)
        .shadow(radius: 2)
    }

    private func color(for s: PanelComputedStatus) -> Color {
        switch s.bucket {
        case .absent: return .black
        case .todo: return .red
        case .upToDate: return .green
        case .old: return .orange
        case .pendingSync: return .blue
        case .overposted: return .blue   // ✅ adversaires
        }
    }
}
