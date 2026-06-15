// ContentView.swift — Root view: routes between ConnectionView and MainView.

import SwiftUI

struct ContentView: View {
    @State private var vm = AntennaViewModel()

    var body: some View {
        Group {
            switch vm.connectionState {
            case .connected:
                MainView(vm: vm)
                    .transition(.opacity)
            default:
                ConnectionView(vm: vm)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.connectionState.isConnected)
        .focusedSceneValue(\.dahlStarVM, vm)
    }
}

#Preview {
    ContentView()
}
