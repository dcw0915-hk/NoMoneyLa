//
//  ContentView.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

// ContentView.swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var langManager: LanguageManager

    var body: some View {
        VStack {
            Text(langManager.localized("transactions_title"))
                .font(.largeTitle)
                .padding()
            Spacer()
        }
    }
}
