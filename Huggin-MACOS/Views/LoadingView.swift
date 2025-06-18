import SwiftUI

struct LoadingView: View {
    @State private var progress: Double = 0
    @State private var currentTask = "Initializing..."
    @State private var currentIndex = 0
    @State private var timer: Timer?
    
    let tasks = [
        "Initializing...",
        "Checking system health...",
        "Scanning for updates...",
        "Loading metrics...",
        "Almost ready..."
    ]
    
    var body: some View {
        ZStack {
            // Background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "shield.checkerboard")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Huggin")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.black)
                }
                
                // Progress Bar
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .frame(width: 200)
                    
                    Text(currentTask)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            startLoading()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startLoading() {
        let totalTasks = Double(tasks.count)
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if currentIndex < tasks.count {
                    withAnimation {
                        currentTask = tasks[currentIndex]
                        progress = Double(currentIndex + 1) / totalTasks
                    }
                    currentIndex += 1
                } else {
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
} 