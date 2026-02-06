//
//  CoverageBar.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import SwiftUI

struct CoverageBar: View {
    let progress: Double  // 0...1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let p = max(0, min(progress, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(.black.opacity(0.10))

                RoundedRectangle(cornerRadius: h/2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: w * p)
                    .animation(.easeInOut(duration: 0.25), value: p)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Progression recouvrement")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}
