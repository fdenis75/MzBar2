import SwiftUI

struct ProcessingQueueView: View {
    @ObservedObject var viewModel: MosaicViewModel
    private let queueWidth: CGFloat = 300
    private let spacing: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: spacing) {
                // Queue Section with LazyVStack
                QueueSection(
                    title: "Queue",
                    icon: "arrow.right.circle",
                    files: viewModel.queuedFiles.prefix(50).filter { !$0.isComplete && !$0.isCancelled }
                )
                
                ProcessingIndicator()
                
                // Completed Section with LazyVStack
                QueueSection(
                    title: "Completed",
                    icon: "checkmark.circle",
                    files: viewModel.completedFiles.prefix(50)
                )
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct QueueSection: View {
    let title: String
    let icon: String
    let files: any Sequence<FileProgress>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text("\(files.underestimatedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Files List with LazyVStack
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(files), id: \.id) { file in
                        FileCard(file: file)
                                .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))

                    }
                }
            }
            .frame(height: 200)
        }
        .frame(width: 300)
    }
}

private struct FileCard: View {
    let file: FileProgress
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // File Icon
            Image(systemName: "doc.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
            
            // Filename
            Text(URL(fileURLWithPath: file.filename).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 12))
            
            Spacer()
            
            // Progress Indicator
            if !file.isComplete && !file.isCancelled && !file.isSkipped && !file.isError {
                ProgressView()
                    .scaleEffect(0.5)
            }
            
            // Status Icon
            Group {
                if file.isCancelled {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if file.isSkipped {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.yellow)
                } else if file.isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if file.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.system(size: 12))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.quaternarySystemFill))
                .opacity(isHovered ? 0.8 : 0.5)
        )
        .onHover { isHovered = $0 }
        .help(file.isError ? (file.errorMessage ?? "Error processing file") : "")
    }
}

private struct ProcessingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// Preview
#Preview {
    ProcessingQueueView(viewModel: MosaicViewModel())
} 