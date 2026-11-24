//
//  Screens.swift
//  ゲーム全体の設定・セーブデータ・メニュー画面
//
//  ここに入っているもの
//  ・BallKind        … ボールの色と印（赤○ 青△ 黄□ 緑✕ 黒◇）
//  ・SurvivalRule    … サバイバルのレベル表（ここで難易度を調整）
//  ・Stages          … ステージの一覧
//  ・SaveData        … ランキングの保存
//  ・DevSettings     … 開発者モード（展示前に消す）
//  ・各メニュー画面
//

import SpriteKit
import UIKit

let gameSceneSize = CGSize(width: 1180, height: 820)

// MARK: - ボールの色と印

enum BallKind: Int, CaseIterable {
    case red, blue, yellow, green, black

    var label: String {
        switch self {
        case .red:    return "赤"
        case .blue:   return "青"
        case .yellow: return "黄"
        case .green:  return "緑"
        case .black:  return "黒"
        }
    }
    var color: UIColor {
        switch self {
        case .red:    return .systemRed
        case .blue:   return .systemBlue
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .black:  return UIColor(white: 0.15, alpha: 1)
        }
    }
    /// ボールの上に描く印の色（黄色は白だと見えにくいので暗い色）
    var markColor: UIColor {
        self == .yellow ? UIColor(white: 0, alpha: 0.55) : .white
    }
    /// 色が見分けにくい人のための印：赤○ 青△ 黄□ 緑✕ 黒◇
    func markPath(size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch self {
        case .red:
            path.addEllipse(in: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
        case .blue:
            path.move(to: CGPoint(x: 0, y: s * 1.1))
            path.addLine(to: CGPoint(x: s * 0.95, y: -s * 0.6))
            path.addLine(to: CGPoint(x: -s * 0.95, y: -s * 0.6))
            path.closeSubpath()
        case .yellow:
            path.addRect(CGRect(x: -s * 0.8, y: -s * 0.8, width: s * 1.6, height: s * 1.6))
        case .green:
            path.move(to: CGPoint(x: -s * 0.8, y: -s * 0.8))
            path.addLine(to: CGPoint(x: s * 0.8, y: s * 0.8))
            path.move(to: CGPoint(x: -s * 0.8, y: s * 0.8))
            path.addLine(to: CGPoint(x: s * 0.8, y: -s * 0.8))
        case .black:
            path.move(to: CGPoint(x: 0, y: s * 1.1))
            path.addLine(to: CGPoint(x: s * 0.9, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -s * 1.1))
            path.addLine(to: CGPoint(x: -s * 0.9, y: 0))
            path.closeSubpath()
        }
        return path
    }

    // 動き方は全色共通
    static let radius: CGFloat = 18
    static let damping: CGFloat = 0.4
    static let restitution: CGFloat = 0.4
    static let density: CGFloat = 1
}

// MARK: - サバイバルのレベル表（難易度はここで調整）
//
// 1行が1レベル。ノルマ（quota）の数だけ正解するとすぐ次のレベルへ進む。
// ・レベルが上がってもボールはそのまま。ただし色が増えるときは、画面のボールを全部消す（減点なし）
// ・投入口の数は色の数と同じ
// ・maxOnScreen：画面に同時に出せるボールの数。上限に達したらタイマーを止め、下回ったら0から数え直す
// ・interval：ボールが出る間隔（秒）。maxOnScreen が1なら「ボールが入ってから次が出るまでの時間」になる
// ・hearts：そのレベルで何個目に出したボールをハートにするか（出した数で数える）
//   ノルマの数だけボールを出した後は、heartEvery 個ごとに1個（あと1個でレベルアップのときは出さない）
// ・angle：ボールがななめに出る角度（真下からの度数。左右はランダム）
// ・wallTimes：左右の壁が「ある時間」と「消えている時間」（秒）。左右は交互に消える

enum BumperMode { case none, solid, bouncy }   // solid：跳ねない障害物、bouncy：跳ねる障害物（どちらも動かない）

struct SurvivalLevel {
    let name: String
    let quota: Int?                  // nil なら最後のレベル（終わりなし）
    let colors: Int
    let maxOnScreen: Int?            // nil なら上限なし
    let interval: Double
    var intervalStep: Double = 0     // 間隔が短くなる秒数（最後のレベル用）
    var intervalEvery: Int = 1       // 何個出すごとに intervalStep だけ短くするか
    var minInterval: Double = 0      // いちばん短くなったときの間隔
    var hearts: [Int] = []
    var angle: Double? = nil
    var bouncyWalls = false
    var wallTimes: (on: Double, off: Double)? = nil
    var bumpers: BumperMode = .none
    var flowScale: CGFloat = 1.0     // ボールが落ちる速さの倍率
}

enum SurvivalRule {
    static let lives = 3                    // 最初のライフ
    static let maxLives = 5                 // ライフの上限
    static let heartEvery = 15              // ノルマ分出した後のハートの間隔
    static let maxBallsOnScreen = 50        // これを超えたらゲームオーバー（処理落ち対策）
    static let maxInk: CGFloat = 1200
    static let spawnerSpeeds: [Double] = [0.35, 0.55, 0.75, 0.95, 1.15]   // 投入口ごとの動く速さ
    static let angledSpeed: CGFloat = 200   // ななめに出るボールの速さ
    static let wallWarnTime = 1.0           // 壁が消える前に点滅する時間（「ある時間」に含む）

    /// Lv1から始めて score 個正解したときに到達しているレベルの名前（開発者メニューのテスト記録用）
    static func levelName(forScore score: Int) -> String {
        var remaining = score
        for level in levels {
            guard let quota = level.quota, remaining >= quota else { return level.name }
            remaining -= quota
        }
        return levels.last?.name ?? ""
    }

    static let levels: [SurvivalLevel] = [
        SurvivalLevel(name: "1",   quota: 5,  colors: 2, maxOnScreen: 1, interval: 1.0, flowScale: 0.8),
        SurvivalLevel(name: "2",   quota: 5,  colors: 2, maxOnScreen: 1, interval: 0.5, hearts: [3], flowScale: 0.8),
        SurvivalLevel(name: "3",   quota: 5,  colors: 2, maxOnScreen: 2, interval: 2.6, flowScale: 0.8),
        SurvivalLevel(name: "4",   quota: 5,  colors: 2, maxOnScreen: 2, interval: 2.4, hearts: [3], flowScale: 0.8),
        SurvivalLevel(name: "5",   quota: 5,  colors: 2, maxOnScreen: 3, interval: 2.2, flowScale: 0.8),
        SurvivalLevel(name: "6",   quota: 5,  colors: 2, maxOnScreen: 3, interval: 2.0, hearts: [3], flowScale: 0.8),
        SurvivalLevel(name: "7",   quota: 5,  colors: 3, maxOnScreen: 1, interval: 0.0, flowScale: 0.9),
        SurvivalLevel(name: "7+",  quota: 5,  colors: 3, maxOnScreen: 2, interval: 2.4, hearts: [3], flowScale: 0.9),
        SurvivalLevel(name: "8",   quota: 5,  colors: 3, maxOnScreen: 3, interval: 2.3, flowScale: 0.9),
        SurvivalLevel(name: "8+",  quota: 5,  colors: 3, maxOnScreen: 3, interval: 2.2, hearts: [3], flowScale: 0.9),
        SurvivalLevel(name: "9",   quota: 10, colors: 3, maxOnScreen: 4, interval: 2.0, hearts: [5], flowScale: 0.9),
        SurvivalLevel(name: "9+",  quota: 10, colors: 3, maxOnScreen: 4, interval: 1.8, hearts: [5], flowScale: 0.9),
        SurvivalLevel(name: "10",  quota: 10, colors: 4, maxOnScreen: 2, interval: 2.4, hearts: [5]),
        SurvivalLevel(name: "10+", quota: 10, colors: 4, maxOnScreen: 3, interval: 2.3, hearts: [5]),
        SurvivalLevel(name: "11",  quota: 10, colors: 4, maxOnScreen: 4, interval: 2.2, hearts: [5], angle: 15),
        SurvivalLevel(name: "11+", quota: 10, colors: 4, maxOnScreen: 4, interval: 2.1, hearts: [5], angle: 15),
        SurvivalLevel(name: "12",  quota: 15, colors: 4, maxOnScreen: 4, interval: 2.0, hearts: [9, 10], angle: 30, bouncyWalls: true),
        SurvivalLevel(name: "12+", quota: 15, colors: 4, maxOnScreen: 4, interval: 1.9, hearts: [9, 10], angle: 30, bouncyWalls: true),
        SurvivalLevel(name: "13",  quota: 20, colors: 4, maxOnScreen: 5, interval: 1.6, hearts: [4, 5, 14, 15], angle: 45,
                      bouncyWalls: true, wallTimes: (on: 4.0, off: 0.5)),
        SurvivalLevel(name: "13+", quota: 20, colors: 4, maxOnScreen: 5, interval: 1.5, hearts: [4, 5, 14, 15], angle: 45,
                      bouncyWalls: true, wallTimes: (on: 4.0, off: 1.0)),
        SurvivalLevel(name: "14",  quota: 30, colors: 4, maxOnScreen: 6, interval: 1.2, hearts: [9, 10, 24, 25], angle: 60,
                      bouncyWalls: true, wallTimes: (on: 4.0, off: 1.5), bumpers: .solid),
        SurvivalLevel(name: "14+", quota: 30, colors: 4, maxOnScreen: 6, interval: 1.1, hearts: [4, 5, 19, 20], angle: 60,
                      bouncyWalls: true, wallTimes: (on: 4.0, off: 2.0), bumpers: .bouncy),
        // 最後（隠し）：ギミックなし。5色目が出て、ボールだけがどんどん増える（4個出すごとに0.05秒短く、最短0.1秒）
        SurvivalLevel(name: "15",  quota: nil, colors: 5, maxOnScreen: nil, interval: 2.0, intervalStep: 0.05, intervalEvery: 4,
                      minInterval: 0.1),
    ]
}

// MARK: - ステージ（あそびかたの続き。最初から全部選べる、記録は残さない）

struct StageConfig {
    let title: String
    let detail: String
    let colors: Int               // 色の数（＝箱の数）
    let spawnerSpeeds: [Double]   // 投入口ごとの動く速さ。数が投入口の数
    let ballCount: Int            // ボールの数
    let interval: Double          // ボールが出る間隔（秒）
    let flowScale: CGFloat        // ボールが落ちる速さの倍率

    var kinds: [BallKind] { Array(BallKind.allCases.prefix(colors)) }

    /// 色を同じ数ずつ混ぜた順番（毎回同じ）
    func makeSequence(seed start: UInt64) -> [BallKind] {
        var list: [BallKind] = []
        while list.count < ballCount { list.append(contentsOf: kinds) }
        list = Array(list.prefix(ballCount))
        var seed = start
        for i in stride(from: list.count - 1, to: 0, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((seed >> 33) % UInt64(i + 1))
            list.swapAt(i, j)
        }
        return list
    }
}

enum Stages {
    static let all: [StageConfig] = [
        StageConfig(title: "",     detail: "投入口はひとつ。あわてず線を引こう！",
                    colors: 2, spawnerSpeeds: [0.3],            ballCount: 8,  interval: 3.0, flowScale: 0.7),
        StageConfig(title: "",       detail: "投入口が動くよ！落ちる場所を見てから線を引こう！",
                    colors: 2, spawnerSpeeds: [0.6],            ballCount: 10, interval: 2.8, flowScale: 0.75),
        StageConfig(title: "",   detail: "ボールが2か所から交互に出てくるよ！",
                    colors: 2, spawnerSpeeds: [0.35, 0.55],     ballCount: 12, interval: 2.6, flowScale: 0.8),
        StageConfig(title: "",    detail: "ボールが落ちてくる間隔が短くなったよ！線を早めに準備しよう！",
                    colors: 2, spawnerSpeeds: [0.35, 0.55],     ballCount: 15, interval: 2.0, flowScale: 0.85),
        StageConfig(title: "",      detail: "3色になったよ！まずはゆっくりのペースでやってみよう！",
                    colors: 3, spawnerSpeeds: [0.35, 0.55],     ballCount: 12, interval: 2.8, flowScale: 0.85),
        StageConfig(title: "", detail: "投入口も3つに増えたよ！",
                    colors: 3, spawnerSpeeds: [0.35, 0.55, 0.75], ballCount: 15, interval: 2.6, flowScale: 0.9),
        StageConfig(title: "",    detail: "ボールが落ちてくる間隔が短くなったよ！",
                    colors: 3, spawnerSpeeds: [0.35, 0.55, 0.75], ballCount: 18, interval: 2.0, flowScale: 0.9),
        StageConfig(title: "",      detail: "これが最後のステージ！4色のボールを仕分けしよう！",
                    colors: 4, spawnerSpeeds: [0.35, 0.55, 0.75, 0.95], ballCount: 20, interval: 2.8, flowScale: 1.0),
    ]
}

// MARK: - セーブデータ（ランキング・レバーの位置）

struct RankEntry: Codable {
    let name: String
    let score: Int
    let date: Date
    var level: String? = nil   // 到達レベル（古い記録には無い）
    var isTest: Bool? = nil    // 開発者メニューから登録したテスト記録
}

// MARK: - 学祭の日程（ランキングに「1日目」などと出す）

enum FestivalDays {
    static let year = 2026
    static let days: [(month: Int, day: Int, label: String)] = [
        (11, 20, "1日目"),
        (11, 21, "2日目"),
        (11, 22, "3日目"),
        (11, 23, "4日目"),
    ]
    static let testLabel = "0日目(テストプレイ)"

    /// ランキングに出す「◯日目 時:分」。学祭の日以外の記録は空
    static func label(for entry: RankEntry) -> String {
        let time = timeFormatter.string(from: entry.date)
        if entry.isTest == true { return "\(testLabel) \(time)" }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: entry.date)
        guard c.year == year, let d = days.first(where: { $0.month == c.month && $0.day == c.day }) else { return "" }
        return "\(d.label) \(time)"
    }

    /// 24時間制の「時:分」
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()
}

enum SaveData {
    static let defaults = UserDefaults.standard
    static let rankingSize = 30     // ランキングに残す人数
    static let rankingPageSize = 10 // ランキング画面で一度に見える人数（それより下はスクロールで見る）

    static var ranking: [RankEntry] {
        get {
            guard let data = defaults.data(forKey: "ranking"),
                  let list = try? JSONDecoder().decode([RankEntry].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "ranking")
            }
        }
    }
    /// このスコアがランキングに入るか
    static func qualifies(_ score: Int) -> Bool {
        let list = ranking
        return score > 0 && (list.count < rankingSize || score > (list.last?.score ?? 0))
    }
    /// ランキングに追加して、何番目に入ったかを返す（0が1位）
    static func addRanking(name: String, score: Int, level: String?, date: Date = Date(), isTest: Bool = false) -> Int {
        var list = ranking
        let index = list.firstIndex { score > $0.score } ?? list.count
        list.insert(RankEntry(name: name, score: score, date: date, level: level, isTest: isTest ? true : nil), at: index)
        ranking = Array(list.prefix(rankingSize))
        return index
    }
    static func resetRanking() {
        defaults.removeObject(forKey: "ranking")
    }
    /// ランキングの index 番目（0が1位）の記録を消す
    static func removeRanking(at index: Int) {
        var list = ranking
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        ranking = list
    }

}

// MARK: - 開発者モード（展示前に消す）
//
// タイトルの文字を5秒長押しして、パスコードを入れると開く。アプリを終了するまで有効。
// ランキングのリセットもこの中にある。
// 開発者モード中のスコアはランキングに残らない。

enum DevSettings {
    static let passcode = "0000"      // 開発者メニューに入るためのパスコード（展示前に必ず変えてください）
    static var invincible = false     // ミスしてもライフが減らない
    static var startLevel = 0         // サバイバルを何番目のレベルから始めるか
    static var isActive: Bool { invincible || startLevel > 0 }
}

// MARK: - デモプレイ（タイトル画面で放置されたときの自動プレイ）

enum DemoSettings {
    static let idleSeconds = 120.0     // タイトル画面で何秒放置したらデモを始めるか
    static let length = 60.0           // デモを何秒流したらタイトルへ戻るか
    static let colors = 3              // デモで使う色の数（＝投入口の数）
    static let interval = 1.6          // デモでボールが出る間隔（秒）
    static let captionTime = 5.0       // 説明文1つを表示する秒数
    static let bannerText = "デモプレイ中　画面をタッチするとメニューにもどるよ！"
    // 順番に表示する説明文（「レバー」を含む説明の間は、レバーを動かして見せる）
    static let captions = [
        "ボールは上の投入口から落ちてくるよ！",
        "指で線を描くと、ボールが跳ねて向きが変わるよ！",
        "ボールと同じ色の箱に入れよう！",
        "上のレバーで落ちる速さを変えられるよ！",
        "♥マークのボールを入れるとライフが増えるよ！",
        "サバイバルでランキング上位を目指そう！",
    ]
}

// MARK: - 画面づくりの共通部品

extension SKNode {
    @discardableResult
    func addButton(_ text: String, name: String, at position: CGPoint,
                   size: CGSize = CGSize(width: 240, height: 64), fontSize: CGFloat = 24,
                   fill: UIColor = .white) -> SKShapeNode {
        let button = SKShapeNode(rectOf: size, cornerRadius: 14)
        button.fillColor = fill
        button.strokeColor = .darkGray
        button.lineWidth = 2
        button.position = position
        button.name = name
        button.zPosition = 20
        let label = SKLabelNode(fontNamed: "HiraginoSans-W6")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = .darkGray
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)
        addChild(button)
        return button
    }

    @discardableResult
    func addLabel(_ text: String, at position: CGPoint, fontSize: CGFloat,
                  color: UIColor = .darkGray, bold: Bool = true,
                  align: SKLabelHorizontalAlignmentMode = .center) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: bold ? "HiraginoSans-W6" : "HiraginoSans-W3")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = align
        label.verticalAlignmentMode = .center
        label.position = position
        addChild(label)
        return label
    }
}

extension SKScene {
    /// 別の画面へ切り替える
    func go(to scene: SKScene) {
        scene.scaleMode = .aspectFit
        view?.presentScene(scene, transition: .fade(withDuration: 0.25))
    }
    /// タッチした場所にあるボタンの名前
    func tappedName(_ touches: Set<UITouch>) -> String? {
        guard let touch = touches.first else { return nil }
        return buttonName(at: touch.location(in: self))
    }
    func buttonName(at point: CGPoint) -> String? {
        nodes(at: point).compactMap { $0.name }.first
    }
    /// 確認ダイアログや名前入力を出すための画面
    func topViewController() -> UIViewController? {
        var vc = view?.window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

// MARK: - タイトル画面

final class MenuScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        let title = addLabel("ColorBump", at: CGPoint(x: frame.midX, y: frame.maxY - 190), fontSize: 80)
        title.name = "title"
        addLabel("落ちてくるボールを、跳ねる線を描いて同じ色の箱へ入れよう！", at: CGPoint(x: frame.midX, y: frame.maxY - 270),
                 fontSize: 24, color: .gray, bold: false)

        // 飾りのボール（5色目の黒は隠し要素なので出さない）
        for (i, kind) in BallKind.allCases.prefix(4).enumerated() {
            let ball = SKShapeNode(circleOfRadius: 22)
            ball.fillColor = kind.color
            ball.strokeColor = .clear
            ball.position = CGPoint(x: frame.midX - 120 + CGFloat(i) * 80, y: frame.maxY - 340)
            let mark = SKShapeNode(path: kind.markPath(size: 9))
            mark.strokeColor = kind.markColor
            mark.lineWidth = 3
            ball.addChild(mark)
            addChild(ball)
        }

        addButton("あそぶ", name: "survival", at: CGPoint(x: frame.midX, y: 360),
                  size: CGSize(width: 340, height: 80), fontSize: 32)
        addButton("あそびかた", name: "tutorial", at: CGPoint(x: frame.midX - 88, y: 265),
                  size: CGSize(width: 164, height: 68), fontSize: 24)
        addButton("ステージ", name: "stages", at: CGPoint(x: frame.midX + 88, y: 265),
                  size: CGSize(width: 164, height: 68), fontSize: 24)
        addButton("ランキング", name: "ranking", at: CGPoint(x: frame.midX, y: 180),
                  size: CGSize(width: 340, height: 68), fontSize: 26)


        if let best = SaveData.ranking.first {
            addLabel("最高記録：\(best.score)（\(best.name)）", at: CGPoint(x: frame.midX, y: 90),
                     fontSize: 20, color: .gray, bold: false)
        }
        if DevSettings.isActive {
            addLabel("開発者モード中", at: CGPoint(x: 120, y: 60), fontSize: 18, color: .systemRed)
        }
        startIdleTimer()
    }

    /// しばらく触られなかったらデモプレイを流す
    func startIdleTimer() {
        removeAction(forKey: "idle")
        run(.sequence([.wait(forDuration: DemoSettings.idleSeconds), .run { [weak self] in
            self?.go(to: GameScene(size: gameSceneSize, mode: .demo))
        }]), withKey: "idle")
    }

    /// 開発者メニューに入る前にパスコードを聞く
    func askPasscode() {
        guard let vc = topViewController() else { return }
        removeAction(forKey: "idle")   // 入力中にデモが始まらないように
        let alert = UIAlertController(title: "開発者メニュー", message: "パスコードを入力してください", preferredStyle: .alert)
        alert.addTextField {
            $0.isSecureTextEntry = true
            $0.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { [weak self] _ in
            self?.startIdleTimer()
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if alert.textFields?.first?.text == DevSettings.passcode {
                self?.go(to: DevScene(size: gameSceneSize))
            } else {
                self?.startIdleTimer()
            }
        })
        vc.present(alert, animated: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        startIdleTimer()   // 触られたら放置の時間を数え直す
        switch tappedName(touches) {
        case "survival": go(to: GameScene(size: gameSceneSize, mode: .survival))
        case "tutorial": go(to: TutorialSelectScene(size: gameSceneSize))
        case "stages":   go(to: StageSelectScene(size: gameSceneSize))
        case "ranking":  go(to: RankingScene(size: gameSceneSize, highlight: nil))
        case "title":
            // 開発者モード：5秒長押し（展示前に消す）
            run(.sequence([.wait(forDuration: 5), .run { [weak self] in
                self?.askPasscode()
            }]), withKey: "devHold")
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeAction(forKey: "devHold")
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeAction(forKey: "devHold")
    }
}

// MARK: - 開発者モード画面（展示前に消す）

final class DevScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.88, alpha: 1)
        addLabel("開発者モード", at: CGPoint(x: frame.midX, y: frame.maxY - 70), fontSize: 36, color: .systemRed)
        addLabel("ここでの設定中のスコアはランキングに残りません", at: CGPoint(x: frame.midX, y: frame.maxY - 115),
                 fontSize: 18, color: .gray, bold: false)

        addButton("テスト記録を登録", name: "addRecord", at: CGPoint(x: frame.maxX - 170, y: frame.maxY - 130),
                  size: CGSize(width: 260, height: 52), fontSize: 20, fill: UIColor.systemBlue.withAlphaComponent(0.15))
        addButton("記録を選んで消す", name: "deleteRecord", at: CGPoint(x: 170, y: frame.maxY - 130),
                  size: CGSize(width: 260, height: 52), fontSize: 20, fill: UIColor.systemRed.withAlphaComponent(0.12))
        addButton("ランキングをリセット", name: "resetRanking", at: CGPoint(x: frame.maxX - 170, y: frame.maxY - 70),
                  size: CGSize(width: 260, height: 52), fontSize: 20, fill: UIColor.systemRed.withAlphaComponent(0.2))

        addButton("無敵：\(DevSettings.invincible ? "ON" : "OFF")", name: "invincible",
                  at: CGPoint(x: frame.midX, y: frame.maxY - 180), size: CGSize(width: 260, height: 56))

        addLabel("開始レベル", at: CGPoint(x: frame.midX, y: frame.maxY - 250), fontSize: 24)
        let levels = SurvivalRule.levels
        let columns = 7
        for (i, level) in levels.enumerated() {
            let col = i % columns, row = i / columns
            let x = frame.midX + (CGFloat(col) - CGFloat(columns - 1) / 2) * 130
            let y = frame.maxY - 320 - CGFloat(row) * 80
            let selected = i == DevSettings.startLevel
            addButton("Lv\(level.name)", name: "lv_\(i)", at: CGPoint(x: x, y: y), size: CGSize(width: 116, height: 60),
                      fontSize: 22, fill: selected ? UIColor.systemYellow.withAlphaComponent(0.6) : .white)
        }

        addButton("この設定で遊ぶ", name: "play", at: CGPoint(x: frame.midX - 230, y: 90), size: CGSize(width: 280, height: 64))
        addButton("通常に戻す", name: "reset", at: CGPoint(x: frame.midX + 60, y: 90), size: CGSize(width: 220, height: 64))
        addButton("メニュー", name: "menu", at: CGPoint(x: frame.midX + 300, y: 90), size: CGSize(width: 200, height: 64))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let name = tappedName(touches) else { return }
        switch name {
        case "invincible":
            DevSettings.invincible.toggle()
            go(to: DevScene(size: gameSceneSize))
        case "play":
            go(to: GameScene(size: gameSceneSize, mode: .survival))
        case "reset":
            DevSettings.invincible = false
            DevSettings.startLevel = 0
            go(to: MenuScene(size: gameSceneSize))
        case "menu":
            go(to: MenuScene(size: gameSceneSize))
        case "resetRanking":
            confirmResetRanking()
        case "addRecord":
            askTestRecord()
        case "deleteRecord":
            go(to: RankingScene(size: gameSceneSize, highlight: nil, deleteMode: true))
        default:
            if name.hasPrefix("lv_"), let i = Int(name.dropFirst(3)) {
                DevSettings.startLevel = i
                go(to: DevScene(size: gameSceneSize))
            }
        }
    }
}

extension DevScene {
    /// 名前・点数・レベル・時間を入れて、テスト記録としてランキングに登録する
    func askTestRecord() {
        guard let vc = topViewController() else { return }
        let alert = UIAlertController(title: "テスト記録を登録",
                                      message: "ランキングには「\(FestivalDays.testLabel)」と表示されます", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名前（15文字まで）" }
        alert.addTextField {
            $0.placeholder = "点数"
            $0.keyboardType = .numberPad
        }
        alert.addTextField {
            $0.placeholder = "時間（例：14:05　空欄なら今の時間）"
            $0.keyboardType = .numbersAndPunctuation
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "登録", style: .default) { [weak self] _ in
            let fields = alert.textFields ?? []
            let name = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let score = Int(fields[1].text ?? ""), score >= 0 else {
                self?.showMessage("点数が正しくありません")
                return
            }
            let date = DevScene.parseTime(fields[2].text ?? "") ?? Date()
            let rank = SaveData.addRanking(name: name.isEmpty ? "テスト" : String(name.prefix(15)), score: score,
                                           level: SurvivalRule.levelName(forScore: score), date: date, isTest: true)
            if rank < SaveData.rankingSize {
                self?.go(to: RankingScene(size: gameSceneSize, highlight: rank))
            } else {
                self?.showMessage("点数が低いため、ランキング（上位\(SaveData.rankingSize)人）に入りませんでした")
            }
        })
        vc.present(alert, animated: true)
    }

    /// 「14:05」「1405」「14」などを今日のその時刻にする
    static func parseTime(_ text: String) -> Date? {
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        var hour = 0, minute = 0
        if text.contains(":") || text.contains("：") {
            let parts = text.split(whereSeparator: { $0 == ":" || $0 == "：" })
            hour = Int(parts.first ?? "") ?? -1
            minute = parts.count > 1 ? (Int(parts[1]) ?? -1) : 0
        } else if digits.count <= 2 {
            hour = Int(digits) ?? -1
        } else {
            hour = Int(digits.dropLast(2)) ?? -1
            minute = Int(digits.suffix(2)) ?? -1
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    func showMessage(_ text: String) {
        guard let vc = topViewController() else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(alert, animated: true)
    }

    func confirmResetRanking() {
        guard let vc = topViewController() else { return }
        let alert = UIAlertController(title: "ランキングを消しますか？", message: "この操作は取り消せません", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "消す", style: .destructive) { _ in
            SaveData.resetRanking()
        })
        vc.present(alert, animated: true)
    }
}

// MARK: - あそびかた（お題の一覧。最初から全部選べる）

final class TutorialSelectScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        addLabel("あそびかた", at: CGPoint(x: frame.midX, y: frame.maxY - 80), fontSize: 40)
        addButton("もどる", name: "back", at: CGPoint(x: 140, y: frame.maxY - 80), size: CGSize(width: 180, height: 56))

        let steps = GameScene.tutorialSteps
        let cardSize = CGSize(width: 250, height: 260)
        for (i, step) in steps.enumerated() {
            let x = frame.midX + (CGFloat(i) - CGFloat(steps.count - 1) / 2) * (cardSize.width + 24)
            let card = SKShapeNode(rectOf: cardSize, cornerRadius: 16)
            card.fillColor = .white
            card.strokeColor = .darkGray
            card.lineWidth = 2
            card.position = CGPoint(x: x, y: frame.midY + 20)
            card.name = "lesson_\(i)"
            addChild(card)

            card.addLabel("お題\(i + 1)", at: CGPoint(x: 0, y: 80), fontSize: 34).name = card.name
            // タイトルはカードの幅で折り返す
            let titleLabel = card.addLabel(step.title, at: CGPoint(x: 0, y: 5), fontSize: 21, bold: false)
            titleLabel.numberOfLines = 0
            titleLabel.preferredMaxLayoutWidth = cardSize.width - 40
            titleLabel.name = card.name
        }
        addLabel("どのお題からでも遊べるよ！", at: CGPoint(x: frame.midX, y: 120), fontSize: 20, color: .gray, bold: false)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let name = tappedName(touches) else { return }
        if name == "back" {
            go(to: MenuScene(size: gameSceneSize))
        } else if name.hasPrefix("lesson_"), let i = Int(name.dropFirst(7)) {
            go(to: GameScene(size: gameSceneSize, mode: .tutorial(i)))
        }
    }
}

// MARK: - ステージ選択（最初から全部選べる）

final class StageSelectScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        addLabel("ステージ", at: CGPoint(x: frame.midX, y: frame.maxY - 80), fontSize: 40)
        addButton("もどる", name: "back", at: CGPoint(x: 140, y: frame.maxY - 80), size: CGSize(width: 180, height: 56))

        let columns = 4
        let cardSize = CGSize(width: 250, height: 210)
        for (i, stage) in Stages.all.enumerated() {
            let col = i % columns, row = i / columns
            let x = frame.midX + (CGFloat(col) - CGFloat(columns - 1) / 2) * (cardSize.width + 24)
            let y = frame.maxY - 280 - CGFloat(row) * (cardSize.height + 28)
            let card = SKShapeNode(rectOf: cardSize, cornerRadius: 16)
            card.fillColor = .white
            card.strokeColor = .darkGray
            card.lineWidth = 2
            card.position = CGPoint(x: x, y: y)
            card.name = "stage_\(i)"
            addChild(card)

            let hasTitle = !stage.title.isEmpty
            card.addLabel("\(i + 1)", at: CGPoint(x: 0, y: hasTitle ? 60 : 30), fontSize: hasTitle ? 44 : 56).name = card.name
            if hasTitle {
                card.addLabel(stage.title, at: CGPoint(x: 0, y: 5), fontSize: 22, bold: false).name = card.name
            }
            for (j, kind) in stage.kinds.enumerated() {
                let dot = SKShapeNode(circleOfRadius: 12)
                dot.fillColor = kind.color
                dot.strokeColor = .clear
                dot.position = CGPoint(x: (CGFloat(j) - CGFloat(stage.colors - 1) / 2) * 32, y: stage.title.isEmpty ? -45 : -50)
                dot.name = card.name
                card.addChild(dot)
            }
        }
        addLabel("どのステージからでも遊べるよ！", at: CGPoint(x: frame.midX, y: 60),
                 fontSize: 20, color: .gray, bold: false)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let name = tappedName(touches) else { return }
        if name == "back" {
            go(to: MenuScene(size: gameSceneSize))
        } else if name.hasPrefix("stage_"), let i = Int(name.dropFirst(6)) {
            go(to: GameScene(size: gameSceneSize, mode: .stage(i)))
        }
    }
}

// MARK: - ランキング画面

final class RankingScene: SKScene {
    let highlight: Int?   // 今回入った順位（強調表示する）
    let deleteMode: Bool  // 開発者メニューから開いた「記録を選んで消す」画面
    var initialOffset: CGFloat?

    // 全員を1つの表にならべて、上下にスクロールして見る
    let rowHeight: CGFloat = 50
    let listNode = SKNode()             // 全部の行をのせて、上下に動かす
    var listTop: CGFloat = 0            // いちばん上までスクロールしたときの listNode の高さ
    var visibleRect = CGRect.zero       // 行が見える範囲
    var offset: CGFloat = 0             // どれだけ下へスクロールしたか
    var maxOffset: CGFloat = 0
    var velocity: CGFloat = 0           // 指を離したあとの、すべる速さ
    var touchStart: CGPoint?
    var offsetAtTouch: CGFloat = 0
    var lastTouchY: CGFloat = 0
    var lastTouchTime: TimeInterval = 0
    var dragging = false
    var lastUpdate: TimeInterval = 0
    let scrollBar = SKShapeNode()

    init(size: CGSize, highlight: Int?, deleteMode: Bool = false, offset: CGFloat? = nil) {
        self.highlight = highlight
        self.deleteMode = deleteMode
        self.initialOffset = offset
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        let title = addLabel(deleteMode ? "消す記録をタッチ" : "ランキング", at: CGPoint(x: frame.midX, y: frame.maxY - 70),
                             fontSize: 40, color: deleteMode ? .systemRed : .darkGray)
        title.zPosition = 20

        let list = SaveData.ranking
        if list.isEmpty {
            addLabel("まだ記録がありません", at: CGPoint(x: frame.midX, y: frame.midY + 40), fontSize: 26, color: .gray)
        }

        // 見える範囲（10人分）で切り抜いて、その中で全部の行を上下に動かす
        let visibleHeight = rowHeight * CGFloat(SaveData.rankingPageSize)
        listTop = frame.maxY - 150
        visibleRect = CGRect(x: 0, y: listTop - visibleHeight + rowHeight / 2, width: frame.width, height: visibleHeight)
        maxOffset = max(0, rowHeight * CGFloat(list.count) - visibleHeight)
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: visibleRect.size)
        mask.position = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        crop.maskNode = mask
        addChild(crop)
        crop.addChild(listNode)

        for (i, entry) in list.enumerated() {
            let y = -CGFloat(i) * rowHeight   // listNode の中での位置
            if i == highlight {
                let band = SKShapeNode(rectOf: CGSize(width: 1000, height: 44), cornerRadius: 10)
                band.fillColor = UIColor.systemYellow.withAlphaComponent(0.35)
                band.strokeColor = .clear
                band.position = CGPoint(x: frame.midX, y: y)
                listNode.addChild(band)
            }
            if deleteMode {
                // 行全体をタッチできるようにする
                let row = SKShapeNode(rectOf: CGSize(width: 1000, height: 44), cornerRadius: 10)
                row.fillColor = UIColor.white.withAlphaComponent(0.6)
                row.strokeColor = UIColor.systemRed.withAlphaComponent(0.4)
                row.position = CGPoint(x: frame.midX, y: y)
                row.name = "row_\(i)"
                listNode.addChild(row)
            }
            let color: UIColor = i < 3 ? .systemOrange : .darkGray
            listNode.addLabel("\(i + 1)位", at: CGPoint(x: frame.midX - 470, y: y), fontSize: 26, color: color, align: .left)
            listNode.addLabel(entry.name, at: CGPoint(x: frame.midX - 390, y: y), fontSize: 22, align: .left)   // 15文字まで入る幅
            // 「1日目 14:05」など（学祭の日以外の記録は空）
            listNode.addLabel(FestivalDays.label(for: entry), at: CGPoint(x: frame.midX - 40, y: y), fontSize: 16,
                              color: .gray, bold: false, align: .left)
            listNode.addLabel(entry.level.map { "Lv\($0)" } ?? "", at: CGPoint(x: frame.midX + 255, y: y), fontSize: 22,
                              color: .gray, align: .left)
            listNode.addLabel("\(entry.score)", at: CGPoint(x: frame.midX + 470, y: y), fontSize: 28, color: color, align: .right)
        }

        // スクロールの位置を示す細いバー（全員が入りきらないときだけ）
        if maxOffset > 0 {
            scrollBar.fillColor = UIColor.gray.withAlphaComponent(0.5)
            scrollBar.strokeColor = .clear
            addChild(scrollBar)
        }

        // 最初の位置：今回入った順位が見えるように（指定があればその位置）
        if let start = initialOffset {
            offset = start
        } else if let h = highlight {
            offset = CGFloat(h) * rowHeight - visibleHeight / 2 + rowHeight / 2
        }
        offset = max(0, min(maxOffset, offset))
        applyOffset()

        if deleteMode {
            addButton("開発者メニューへ", name: "dev", at: CGPoint(x: frame.midX, y: 70), size: CGSize(width: 280, height: 64))
            return
        }
        addButton("もう一度あそぶ", name: "survival", at: CGPoint(x: frame.midX - 150, y: 70), size: CGSize(width: 280, height: 64))
        addButton("メニュー", name: "menu", at: CGPoint(x: frame.midX + 150, y: 70), size: CGSize(width: 280, height: 64))
    }

    func applyOffset() {
        listNode.position.y = listTop + offset
        guard maxOffset > 0 else { return }
        let ratio = visibleRect.height / (visibleRect.height + maxOffset)
        let barHeight = max(30, visibleRect.height * ratio)
        let progress = max(0, min(1, offset / maxOffset))
        let barY = visibleRect.maxY - barHeight - (visibleRect.height - barHeight) * progress
        scrollBar.path = CGPath(roundedRect: CGRect(x: frame.maxX - 34, y: barY, width: 6, height: barHeight),
                                cornerWidth: 3, cornerHeight: 3, transform: nil)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.05)
        lastUpdate = currentTime
        guard touchStart == nil, dt > 0 else { return }
        // 指を離したあとは、少しすべってから止まる
        if abs(velocity) > 5 {
            offset += velocity * CGFloat(dt)
            velocity *= CGFloat(pow(0.92, dt * 60))
        } else {
            velocity = 0
        }
        // はみ出したら、ばねのように戻る
        if offset < 0 {
            offset += (0 - offset) * CGFloat(min(1, dt * 12))
            if velocity < 0 { velocity = 0 }
        } else if offset > maxOffset {
            offset += (maxOffset - offset) * CGFloat(min(1, dt * 12))
            if velocity > 0 { velocity = 0 }
        }
        applyOffset()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        touchStart = point
        offsetAtTouch = offset
        lastTouchY = point.y
        lastTouchTime = touch.timestamp
        velocity = 0
        dragging = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = touchStart, maxOffset > 0 else { return }
        let point = touch.location(in: self)
        let dy = point.y - start.y
        if abs(dy) > 10 { dragging = true }
        guard dragging else { return }
        // 指に合わせて動かす（端より先は少しだけ動く）
        var newOffset = offsetAtTouch + dy
        if newOffset < 0 { newOffset *= 0.3 }
        if newOffset > maxOffset { newOffset = maxOffset + (newOffset - maxOffset) * 0.3 }
        offset = newOffset
        // 指を離したあとにすべらせるための速さ
        let time = touch.timestamp - lastTouchTime
        if time > 0 { velocity = (point.y - lastTouchY) / CGFloat(time) }
        lastTouchY = point.y
        lastTouchTime = touch.timestamp
        applyOffset()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchStart = nil
        if !dragging {
            velocity = 0
            handleTap(at: touch.location(in: self))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }

    func handleTap(at point: CGPoint) {
        switch buttonName(at: point) {
        case "survival": go(to: GameScene(size: gameSceneSize, mode: .survival))
        case "menu":     go(to: MenuScene(size: gameSceneSize))
        case "dev":      go(to: DevScene(size: gameSceneSize))
        case let name? where deleteMode && name.hasPrefix("row_") && visibleRect.contains(point):
            if let i = Int(name.dropFirst(4)) { confirmDelete(i) }
        default: break
        }
    }

    /// 開発者メニュー：選んだ記録を確認してから消す
    func confirmDelete(_ index: Int) {
        let list = SaveData.ranking
        guard list.indices.contains(index), let vc = topViewController() else { return }
        let entry = list[index]
        let alert = UIAlertController(title: "この記録を消しますか？",
                                      message: "\(index + 1)位　\(entry.name)　\(entry.score)点", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "消す", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            SaveData.removeRanking(at: index)
            self.go(to: RankingScene(size: gameSceneSize, highlight: nil, deleteMode: true, offset: self.offset))
        })
        vc.present(alert, animated: true)
    }
}
