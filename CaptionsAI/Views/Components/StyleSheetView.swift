import SwiftUI

// MARK: - StyleSheetView

/// Bottom sheet for selecting caption styles and adjusting text size.
struct StyleSheetView: View {
    @Binding var selectedStyle: CaptionStyle
    @Binding var fontSize: CGFloat
    let previewText: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            // Title
            Text("Caption Style")
                .font(.headline)
                .foregroundColor(.white)
            
            // Style cards - horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CaptionStyle.presets) { style in
                        StylePreviewCard(
                            style: style,
                            isSelected: selectedStyle.name == style.name,
                            previewText: previewText
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
            
            // Text Size Slider
            VStack(spacing: 8) {
                HStack {
                    Text("Text Size")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(fontSize))pt")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.white)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $fontSize, in: 16...48, step: 2)
                        .tint(Color(hex: "#7C3AED"))
                    
                    Image(systemName: "textformat.size.larger")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Style Preview Card

private struct StylePreviewCard: View {
    let style: CaptionStyle
    let isSelected: Bool
    let previewText: String
    
    /// Clamp preview text to fit the card
    private var displayText: String {
        let words = previewText.split(separator: " ")
        let short = words.prefix(3).joined(separator: " ")
        return short.isEmpty ? "Hello" : short
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Preview box
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 100, height: 60)
                
                Text(displayText)
                    .font(.system(size: 12, weight: style.fontName.contains("Bold") ? .bold : (style.fontName.contains("Light") ? .light : .regular)))
                    .foregroundColor(style.textColor.color)
                    .shadow(
                        color: style.shadowColor.color.opacity(style.shadowRadius > 0 ? 0.8 : 0),
                        radius: min(style.shadowRadius, 4)
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Group {
                            if style.backgroundOpacity > 0 {
                                RoundedRectangle(cornerRadius: style.cornerRadius > 0 ? 4 : 0)
                                    .fill(style.backgroundColor.color.opacity(style.backgroundOpacity))
                            }
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(hex: "#7C3AED") : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            
            // Style name
            Text(style.name)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? Color(hex: "#7C3AED") : .secondary)
        }
    }
}
