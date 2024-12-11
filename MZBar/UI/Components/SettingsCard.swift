import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let viewModel: MosaicViewModel
    @ViewBuilder let content: Content
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(viewModel.currentTheme.colors.primary)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(20)
        .background(Material.ultraThinMaterial)
        .opacity(isHovered ? 1 : 0.5)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovered ? viewModel.currentTheme.colors.primary : 
                       Color.gray.opacity(0.3), lineWidth: isHovered ? 2 : 1)
        )
        .animation(.spring(), value: isHovered)
        .onHover { hovering in
            withAnimation {
                isHovered = hovering
            }
        }
    }
} 