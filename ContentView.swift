//
//  ContentView.swift
//  ゲーム画面（SKView）を表示し、タイトル画面から始める
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    var body: some View {
        GameContainer()
            .ignoresSafeArea()
            .statusBarHidden()
    }
}

/// 画面の切り替え（タイトル → ゲーム → ランキング…）ができるように、SKView を直接使う
struct GameContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = true   // レバーを押さえながら線を引けるように
        let scene = MenuScene(size: gameSceneSize)
        scene.scaleMode = .aspectFit
        view.presentScene(scene)
        UIApplication.shared.isIdleTimerDisabled = true   // 遊んでいる間に画面が暗くならないように
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}
