import SwiftUI

struct CelebrationView: View {
    @State private var isAnimating = false

    private let pieces: [ConfettiPiece] = [
        .init(x: -220, y: -44, endX: -280, endY: -180, color: .green, size: 9, rotation: -30),
        .init(x: -150, y: -20, endX: -190, endY: -150, color: .blue, size: 7, rotation: 24),
        .init(x: -90, y: -52, endX: -110, endY: -196, color: .pink, size: 10, rotation: 42),
        .init(x: -28, y: -34, endX: -40, endY: -156, color: .orange, size: 8, rotation: -52),
        .init(x: 34, y: -46, endX: 50, endY: -188, color: .purple, size: 9, rotation: 58),
        .init(x: 96, y: -24, endX: 134, endY: -152, color: .mint, size: 7, rotation: -24),
        .init(x: 162, y: -48, endX: 218, endY: -184, color: .yellow, size: 10, rotation: 34),
        .init(x: 222, y: -18, endX: 296, endY: -150, color: .cyan, size: 8, rotation: -46),
        .init(x: -188, y: 28, endX: -260, endY: 138, color: .orange, size: 8, rotation: 62),
        .init(x: -70, y: 40, endX: -112, endY: 164, color: .green, size: 9, rotation: -38),
        .init(x: 70, y: 38, endX: 116, endY: 166, color: .blue, size: 9, rotation: 44),
        .init(x: 190, y: 24, endX: 266, endY: 134, color: .pink, size: 8, rotation: -60)
    ]

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color.gradient)
                    .frame(width: piece.size, height: piece.size * 1.6)
                    .rotationEffect(.degrees(isAnimating ? piece.rotation : 0))
                    .offset(
                        x: isAnimating ? piece.endX : piece.x,
                        y: isAnimating ? piece.endY : piece.y
                    )
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 1.15), value: isAnimating)
            }

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 70, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .scaleEffect(isAnimating ? 1.12 : 0.82)
                    .opacity(isAnimating ? 1.0 : 0.65)

                Text(AppStrings.completed)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)
                    .scaleEffect(isAnimating ? 1.0 : 0.94)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.62), value: isAnimating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = false
            withAnimation {
                isAnimating = true
            }
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
}

struct CelebrationView_Previews: PreviewProvider {
    static var previews: some View {
        CelebrationView()
    }
}
