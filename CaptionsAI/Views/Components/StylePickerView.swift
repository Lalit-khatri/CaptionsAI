import SwiftUI

// MARK: - StylePickerView

/// Horizontal scrollable strip of caption style presets.
struct StylePickerView: View {
    @Binding var selectedStyle: CaptionStyle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CaptionStyle.presets) { style in
                    StyleCard(
                        style: style,
                        isSelected: selectedStyle.name == style.name
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedStyle = style
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Style Card

private struct StyleCard: View {
    let style: CaptionStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 72, height: 44)

                Text("Abc")
                    .font(style.font.weight(.bold))
                    .foregroundColor(style.textColor.color)
                    .shadow(
                        color: style.shadowColor.color,
                        radius: style.shadowRadius > 0 ? 4 : 0
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Group {
                            if style.backgroundOpacity > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                            }
                        }
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.current.accent : .clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(AppTheme.current.accent)
                        .offset(x: 4, y: -4)
                }
            }

            // Label
            Text(style.name)
                .font(.caption2)
                .foregroundColor(isSelected ? .white : .secondary)
        }
    }
}
