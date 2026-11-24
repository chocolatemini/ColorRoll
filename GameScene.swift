//
//  GameScene.swift
//  ゲーム本体（あそびかた／ステージ／サバイバル）
//
//  ・投入口から流れてくるボールを、線を引いてはじき、同じ色の箱へ入れる
//  ・線は数秒で消える。インクは「画面上にある線の量」の上限で、線が消えると戻る
//  ・流れの速さは画面上部のレバーで3段階に切り替える
//  ・あそびかた：短いお題。失敗してもそのお題をやり直すだけ
//  ・ステージ：決まった数のボールを仕分ける
//  ・サバイバル：レベル表（Screens.swift の SurvivalRule）に沿って進む。ライフがなくなったら終了
//

import SpriteKit

final class BallNode: SKNode {
    let kind: BallKind
    let pattern: SKSpriteNode
    var lastKickTime: Double = -1
    var demoHandled = false             // デモ：このボールに線を引くか決めた
    var isLife = false                  // ハートのボール（正しく入れるとライフ+1）
    var stillTime: Double = 0           // ほとんど動いていない時間（引っかかり対策）
    init(kind: BallKind, pattern: SKSpriteNode) {
        self.kind = kind
        self.pattern = pattern
        super.init()
    }
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }
}

/// あそびかたの1つのお題
struct TutorialStep {
    let title: String
    let detail: String
    let balls: [BallKind]
    let spawnerX: CGFloat?           // 投入口の位置（nil なら左右に動く）
    let interval: Double
    let hint: (CGPoint, CGPoint)?    // 「ここに線を引いてみて」の点線
    var allowDrawing: Bool = true    // false のお題では線を引けない（見ているだけ）
    var onlyNearHint: Bool = false   // true なら点線のまわりにしか線を引けない
    var keepLines: Bool = false      // true なら引いた線が消えない
    var waitForLine: Bool = false    // true なら線を1本引き終わるまでボールを出さない
}

final class GameScene: SKScene, SKPhysicsContactDelegate {

    enum Mode { case tutorial(Int), stage(Int), survival, demo }   // tutorial/stage(何番目か)、demo はタイトルで放置したときの自動プレイ
    let mode: Mode

    init(size: CGSize, mode: Mode) {
        self.mode = mode
        super.init(size: size)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    // MARK: 調整用の数値

    let lineLifetime: Double = 3.0      // 線が消えるまでの秒数
    let lineBounce: CGFloat = 0.6       // 線の跳ね返りやすさ（0〜1）
    let lineKick: CGFloat = 220         // 線に当たったときに弾き出す強さ
    let wallKick: CGFloat = 260         // 跳ねる壁に当たったときに弾き出す強さ
    let bumperKick: CGFloat = 320       // 跳ねる障害物（14+）に当たったときに弾き出す強さ
    let hintRadius: CGFloat = 60        // お題2で線を引ける、点線からの距離
    let lineColor = UIColor(red: 0.5, green: 0.3, blue: 0.75, alpha: 1)   // 線の色（どのボールとも被らない紫）
    let lifeRing = UIColor.white        // ハートのボールのふち
    let spawnerSwing: CGFloat = 430     // 投入口が左右に動く幅
    let slowFlow: CGFloat = 0.6         // レバー：ゆっくり
    let normalFlow: CGFloat = 2         // レバー：ふつう
    let fastFlow: CGFloat = 6           // レバー：はやい

    // MARK: あそびかたのお題

    static let tutorialSteps: [TutorialStep] = [
        TutorialStep(title: "ボールは上から流れてくるよ！",
                     detail: "ボールの色と同じ色の箱に入れるとポイントが入るよ！まずは線を描かずに見ていよう",
                     balls: [.red], spawnerX: 305, interval: 1, hint: nil, allowDrawing: false),
        TutorialStep(title: "線を引いてボールをはじこう！",
                     detail: "青いボールを右の青い箱へ入れよう！うすい帯の中の点線をなぞるとボールが落ちてくるよ！",
                     balls: [.blue], spawnerX: 305, interval: 1,
                     hint: (CGPoint(x: 200, y: 470), CGPoint(x: 700, y: 330)),
                     onlyNearHint: true, keepLines: true, waitForLine: true),
        TutorialStep(title: "線は3秒で消えるよ！",
                     detail: "左上のゲージはインクの残りで、無くなると線が書けなくなるから注意！線が消えるとインクは戻ってくるよ！",
                     balls: [.red, .blue, .blue, .red], spawnerX: 450, interval: 2.8, hint: nil),
        TutorialStep(title: "流れの速さを変えてみよう！",
                     detail: "画面の上のレバーで「ゆっくり」「ふつう」「はやい」を切り替えてみよう！",
                     balls: [.blue, .red, .blue, .red], spawnerX: nil, interval: 2.8, hint: nil),
    ]
    var tutorialSteps: [TutorialStep] { GameScene.tutorialSteps }

    // MARK: 固定の値

    let ballCategory: UInt32 = 1
    let lineCategory: UInt32 = 2
    let wallCategory: UInt32 = 4
    let bumperCategory: UInt32 = 8
    let maxSpawners = 5
    let binTop: CGFloat = 150
    let scoreLine: CGFloat = 105
    let spawnY: CGFloat = 680

    struct Bin { let kind: BallKind; let minX: CGFloat; let maxX: CGFloat }

    // MARK: 状態

    enum Phase { case ready, countdown, run, finished }
    var phase: Phase = .ready

    var kinds: [BallKind] = []          // 箱の色
    var maxInk: CGFloat = 1200
    var bins: [Bin] = []
    var lives = 0

    var isSurvival: Bool { if case .survival = mode { return true } else { return false } }
    var isTutorial: Bool { if case .tutorial = mode { return true } else { return false } }
    var isDemo: Bool { if case .demo = mode { return true } else { return false } }
    var demoDrawn = 0                   // デモ：出したボールの数（ときどきハートにする）
    var demoCaptionIndex = -1
    var demoBanner: SKNode?
    var stageIndex: Int? { if case .stage(let i) = mode { return i } else { return nil } }
    var stage: StageConfig? { stageIndex.map { Stages.all[$0] } }
    var totalBalls = 0                  // ステージ：ボールの総数

    // サバイバル用
    var levelIndex = 0
    var level: SurvivalLevel { SurvivalRule.levels[levelIndex] }
    var correctInLevel = 0              // このレベルで正解した数
    var drawnInLevel = 0                // このレベルで出す順番を決めたボールの数（ハートの位置に使う）
    var spawnedInLevel = 0              // このレベルで実際に出したボールの数（間隔の計算に使う）
    var spawnBlockedUntil: Double = 0   // この時刻まではボールを出さない（色が増えた直後の待ち時間）
    var spawnTimer: Double = 0          // 次のボールまでのタイマー（同時出現数の上限中は止まる）
    var devMode = false                 // 開発者モードで遊んでいる

    // あそびかた用
    var tutorialIndex = 0
    var stepPaused = false
    var queue: [BallKind] = []          // あそびかた・ステージでこれから出るボール
    var hintNode: SKNode?

    // 速さレバー
    enum Speed { case slow, normal, fast }
    var flowSpeed: Speed = .normal       // レバーで選んでいる速さ（SKNode の speed と名前が重ならないように）
    var leverRect = CGRect.zero
    var leverSegments: [Speed: SKShapeNode] = [:]
    var currentFlow: CGFloat = 2

    var lastUpdateTime: TimeInterval = 0
    var balls: [BallNode] = []
    var runTime: Double = 0
    var nextSpawnTime: Double = 0
    var spawnCounter = 0
    var correct = 0
    var wrong = 0
    var textureCache: [BallKind: (pattern: SKTexture, shade: SKTexture)] = [:]

    var spawners: [SKNode] = []
    var previews: [SKShapeNode] = []
    var previewMarks: [SKShapeNode] = []
    var previewHearts: [SKLabelNode] = []
    var previewArrows: [SKLabelNode] = []
    var nextKinds: [BallKind?] = []
    var nextIsLife: [Bool] = []
    var nextAngle: [Double] = []        // 次のボールが出る角度（0ならまっすぐ下）
    var spawnerAngles: [Double] = []

    // 壁と障害物
    var sideWalls: [SKShapeNode] = []
    var sideWallPresent = [true, true]
    var wallsBouncy = false
    var wallCycleTime: Double = 0
    var bumpers: [SKShapeNode] = []
    let bumperBaseX: [CGFloat] = [370, 810]

    // 線
    var lines: [SKShapeNode] = []
    var currentPoints: [CGPoint] = []
    var currentLine: SKShapeNode?
    var currentLength: CGFloat = 0
    var inkOnScreen: CGFloat = 0
    weak var drawingTouch: UITouch?
    weak var leverTouch: UITouch?

    // 表示
    let inkBar = SKShapeNode()
    let binLayer = SKNode()
    var scoreLabel: SKLabelNode!
    var messageLabel: SKLabelNode!
    var messageDetailLabel: SKLabelNode!   // 「レベルアップ！」の下に出す説明
    var stepTitleLabel: SKLabelNode!
    var stepDetailLabel: SKLabelNode!
    var lifeSlots: [SKLabelNode] = []
    let levelBarFill = SKShapeNode()     // 次のレベルまでのメーター
    var levelBarLabel: SKLabelNode?
    let levelBarRect = CGRect(x: 300, y: 702, width: 180, height: 14)
    var readyNodes: [SKNode] = []

    // MARK: - 準備

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(white: 0.93, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        if isSurvival {
            devMode = DevSettings.isActive
            levelIndex = min(DevSettings.startLevel, SurvivalRule.levels.count - 1)
            kinds = Array(BallKind.allCases.prefix(level.colors))
            maxInk = SurvivalRule.maxInk
            lives = SurvivalRule.lives
        } else if let stage = stage, let i = stageIndex {
            kinds = stage.kinds
            queue = stage.makeSequence(seed: 20261105 + UInt64(i))
            totalBalls = queue.count
        } else if isDemo {
            kinds = Array(BallKind.allCases.prefix(DemoSettings.colors))
        } else {
            kinds = [.red, .blue]
        }
        if case .tutorial(let i) = mode { tutorialIndex = i }
        bins = makeBins()
        nextKinds = Array(repeating: nil, count: maxSpawners)
        nextIsLife = Array(repeating: false, count: maxSpawners)
        nextAngle = Array(repeating: 0, count: maxSpawners)
        spawnerAngles = (0..<maxSpawners).map { .pi / 2 + Double($0) * 2 * .pi / Double(maxSpawners) }

        buildStage()
        buildHUD()
        buildLever()
        if stage != nil { (0..<activeSpawnerCount).forEach { refill($0) } }
        if isSurvival { applyLevelGimmicks() }
        updateSpawners(deltaTime: 0)
        if isDemo {
            startDemo()
        } else {
            showReady()
        }
    }

    func makeBins() -> [Bin] {
        let left: CGFloat = 20, right: CGFloat = frame.maxX - 20
        let width = (right - left) / CGFloat(kinds.count)
        return kinds.enumerated().map { i, kind in
            Bin(kind: kind, minX: left + width * CGFloat(i), maxX: left + width * CGFloat(i + 1))
        }
    }

    func buildStage() {
        // 外枠：上と下はいつもある。左右は仕掛けで跳ねたり消えたりする
        let border = frame.insetBy(dx: 20, dy: 20)
        for y in [border.minY, border.maxY] {
            let wall = makeBorderLine(from: CGPoint(x: border.minX, y: y), to: CGPoint(x: border.maxX, y: y))
            wall.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: border.minX, y: y), to: CGPoint(x: border.maxX, y: y))
            addChild(wall)
        }
        for x in [border.minX, border.maxX] {
            let wall = makeBorderLine(from: CGPoint(x: x, y: border.minY), to: CGPoint(x: x, y: border.maxY))
            wall.physicsBody = sideWallBody(x: x)
            addChild(wall)
            sideWalls.append(wall)
        }

        // 箱
        addChild(binLayer)
        buildBins()

        // 投入口が動くレール
        let rail = SKShapeNode(rect: CGRect(x: frame.midX - spawnerSwing - 40, y: spawnY - 3,
                                            width: (spawnerSwing + 40) * 2, height: 6), cornerRadius: 3)
        rail.fillColor = UIColor(white: 0.75, alpha: 1)
        rail.strokeColor = .clear
        rail.zPosition = 3
        addChild(rail)

        // 投入口（真ん中に「次に出るボール」が見える）
        for _ in 0..<maxSpawners {
            let nozzle = SKShapeNode(rectOf: CGSize(width: 76, height: 40), cornerRadius: 12)
            nozzle.fillColor = .white
            nozzle.strokeColor = .darkGray
            nozzle.lineWidth = 3
            nozzle.zPosition = 4
            nozzle.position = CGPoint(x: frame.midX, y: spawnY)
            addChild(nozzle)
            spawners.append(nozzle)

            let preview = SKShapeNode(circleOfRadius: 13)
            preview.strokeColor = .clear
            nozzle.addChild(preview)
            previews.append(preview)

            let mark = SKShapeNode()
            mark.lineWidth = 2.5
            preview.addChild(mark)
            previewMarks.append(mark)

            let heart = SKLabelNode(fontNamed: "HiraginoSans-W6")
            heart.text = "♥"
            heart.fontSize = 22
            heart.fontColor = .systemPink
            heart.verticalAlignmentMode = .center
            heart.position = CGPoint(x: 0, y: 34)
            heart.isHidden = true
            nozzle.addChild(heart)
            previewHearts.append(heart)

            let arrow = SKLabelNode(fontNamed: "HiraginoSans-W6")
            arrow.fontSize = 30
            arrow.fontColor = .darkGray
            arrow.verticalAlignmentMode = .center
            arrow.position = CGPoint(x: 0, y: -36)   // 投入口の下に表示
            arrow.isHidden = true
            nozzle.addChild(arrow)
            previewArrows.append(arrow)
        }
    }

    func makeBorderLine(from a: CGPoint, to b: CGPoint) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let node = SKShapeNode(path: path)
        node.strokeColor = .darkGray
        node.lineWidth = 6
        node.lineCap = .square
        return node
    }

    /// 箱を作る（色が増えたときに作り直す）
    func buildBins() {
        binLayer.removeAllChildren()
        for bin in bins {
            let rect = CGRect(x: bin.minX, y: 20, width: bin.maxX - bin.minX, height: binTop - 20)
            let floor = SKShapeNode(rect: rect)
            floor.fillColor = bin.kind.color.withAlphaComponent(0.18)
            floor.strokeColor = .clear
            floor.zPosition = -1
            binLayer.addChild(floor)

            let mark = SKShapeNode(path: bin.kind.markPath(size: 22))
            mark.strokeColor = bin.kind.color
            mark.lineWidth = 6
            mark.position = CGPoint(x: rect.midX - 30, y: 82)
            mark.zPosition = -0.8
            binLayer.addChild(mark)

            let label = binLayer.addLabel(bin.kind.label, at: CGPoint(x: rect.midX + 30, y: 82), fontSize: 30, color: bin.kind.color)
            label.zPosition = -0.8
        }
        for bin in bins.dropFirst() {
            let a = CGPoint(x: bin.minX, y: 20), b = CGPoint(x: bin.minX, y: binTop)
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let divider = SKShapeNode(path: path)
            divider.strokeColor = .darkGray
            divider.lineWidth = 10
            divider.lineCap = .round
            divider.physicsBody = SKPhysicsBody(edgeFrom: a, to: b)
            binLayer.addChild(divider)
        }
    }

    func buildHUD() {
        let inkFrame = SKShapeNode(rect: CGRect(x: 40, y: frame.maxY - 72, width: 220, height: 16), cornerRadius: 8)
        inkFrame.strokeColor = .darkGray
        inkFrame.lineWidth = 2
        addChild(inkFrame)
        inkBar.fillColor = lineColor
        inkBar.strokeColor = .clear
        addChild(inkBar)
        updateInkBar()

        scoreLabel = addLabel("", at: CGPoint(x: 40, y: frame.maxY - 104), fontSize: 22, align: .left)
        messageLabel = addLabel("", at: CGPoint(x: frame.midX, y: frame.midY + 40), fontSize: 44)
        messageLabel.zPosition = 30
        messageDetailLabel = addLabel("", at: CGPoint(x: frame.midX, y: frame.midY + 5), fontSize: 26, color: .darkGray)
        messageDetailLabel.verticalAlignmentMode = .top   // 複数行のときは下へのびる
        messageDetailLabel.numberOfLines = 0
        messageDetailLabel.preferredMaxLayoutWidth = 900
        messageDetailLabel.zPosition = 30
        stepTitleLabel = addLabel("", at: CGPoint(x: frame.midX, y: 590), fontSize: 30)
        stepTitleLabel.zPosition = 6
        stepDetailLabel = addLabel("", at: CGPoint(x: frame.midX, y: 568), fontSize: 20, color: .gray, bold: false)
        stepDetailLabel.verticalAlignmentMode = .top   // 長いときは下へ折り返す
        stepDetailLabel.numberOfLines = 0
        stepDetailLabel.preferredMaxLayoutWidth = 760
        stepDetailLabel.zPosition = 6

        // ライフ：5つの枠。4つ目と5つ目は「上限まで増やせる分」なので点線の枠
        if isSurvival {
            for i in 0..<SurvivalRule.maxLives {
                let x: CGFloat = 300 + CGFloat(i) * 40
                let slot = addLabel("♡", at: CGPoint(x: x, y: frame.maxY - 64), fontSize: 30, color: .systemRed)
                lifeSlots.append(slot)
                if i >= SurvivalRule.lives {
                    let frameRect = CGRect(x: x - 17, y: frame.maxY - 82, width: 34, height: 36)
                    let dashed = SKShapeNode(path: CGPath(roundedRect: frameRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
                        .copy(dashingWithPhase: 0, lengths: [4, 4]))
                    dashed.strokeColor = .gray
                    dashed.lineWidth = 1.5
                    addChild(dashed)
                }
            }
            // 次のレベルまでのメーター（ライフの下）
            levelBarLabel = addLabel("", at: CGPoint(x: levelBarRect.minX, y: levelBarRect.maxY + 12),
                                     fontSize: 14, color: .darkGray, align: .left)
            let barFrame = SKShapeNode(rect: levelBarRect, cornerRadius: 7)
            barFrame.strokeColor = .darkGray
            barFrame.lineWidth = 1.5
            addChild(barFrame)
            levelBarFill.fillColor = .systemOrange
            levelBarFill.strokeColor = .clear
            addChild(levelBarFill)

            if devMode {
                addLabel("DEV", at: CGPoint(x: 900, y: frame.maxY - 64), fontSize: 22, color: .systemRed)
            }
        }

        if !isDemo {
            addButton("やめる", name: "quit", at: CGPoint(x: frame.maxX - 120, y: frame.maxY - 64),
                      size: CGSize(width: 160, height: 52), fontSize: 20)
        }
        updateHUD()
    }

    /// 流れの速さを切り替えるレバー（左右はタイトル画面で選ぶ）
    /// 流れの速さを切り替えるレバー（画面上部に固定。左から ゆっくり・ふつう・はやい）
    func buildLever() {
        let segmentWidth: CGFloat = 104
        let centerX: CGFloat = 660
        let centerY: CGFloat = frame.maxY - 64
        leverRect = CGRect(x: centerX - segmentWidth * 1.5 - 8, y: centerY - 30, width: segmentWidth * 3 + 16, height: 60)

        let back = SKShapeNode(rect: leverRect, cornerRadius: 16)
        back.fillColor = UIColor.white.withAlphaComponent(0.85)
        back.strokeColor = .darkGray
        back.lineWidth = 2
        back.zPosition = 25
        addChild(back)

        let items: [(Speed, String, CGFloat)] = [(.slow, "ゆっくり", centerX - segmentWidth),
                                                 (.normal, "ふつう", centerX),
                                                 (.fast, "はやい", centerX + segmentWidth)]
        for (s, text, x) in items {
            let seg = SKShapeNode(rectOf: CGSize(width: segmentWidth - 8, height: 48), cornerRadius: 12)
            seg.position = CGPoint(x: x, y: centerY)
            seg.strokeColor = .clear
            seg.zPosition = 26
            addChild(seg)
            leverSegments[s] = seg
            let label = seg.addLabel(text, at: .zero, fontSize: 18)
            label.zPosition = 1
        }
        setSpeed(.normal)
    }

    func setSpeed(_ s: Speed) {
        flowSpeed = s
        for (key, seg) in leverSegments {
            let selected = key == s
            switch key {
            case .fast:   seg.fillColor = selected ? UIColor.systemOrange.withAlphaComponent(0.6) : .clear
            case .normal: seg.fillColor = selected ? UIColor.systemGray.withAlphaComponent(0.4) : .clear
            case .slow:   seg.fillColor = selected ? UIColor.systemTeal.withAlphaComponent(0.5) : .clear
            }
        }
    }

    /// レバーの上の位置（左右）から速さを決める
    func setSpeed(atX x: CGFloat) {
        let third = leverRect.width / 3
        if x > leverRect.minX + third * 2 { setSpeed(.fast) }
        else if x > leverRect.minX + third { setSpeed(.normal) }
        else { setSpeed(.slow) }
    }

    func showReady() {
        let step = tutorialSteps[tutorialIndex]
        var title = "お題\(tutorialIndex + 1)：\(step.title)"
        var detail = step.detail
        if isSurvival {
            title = "あそぶ（サバイバルモード）"
            detail = "ミスするとライフが1つ減って、なくなったらゲームオーバー！♥マークの付いたボールを正しく入れるとライフが増えるよ！"
        } else if let stage = stage, let i = stageIndex {
            title = stage.title.isEmpty ? "ステージ\(i + 1)" : "ステージ\(i + 1)：\(stage.title)"
            detail = "\(stage.detail)（\(stage.ballCount)個）"
        }
        // 説明文が長いときは折り返す（最大2行ほど）
        let detailLabel = addLabel(detail, at: CGPoint(x: frame.midX, y: frame.midY + 82), fontSize: 24, bold: false)
        detailLabel.verticalAlignmentMode = .top
        detailLabel.numberOfLines = 0
        detailLabel.preferredMaxLayoutWidth = 820
        readyNodes = [
            addLabel(title, at: CGPoint(x: frame.midX, y: frame.midY + 120), fontSize: 40),
            detailLabel,
            addLabel("流れの速さは、画面の上のレバーで切り替えられるよ！",
                     at: CGPoint(x: frame.midX, y: frame.midY - 15), fontSize: 18, color: .gray, bold: false),
            addButton("スタート", name: "start", at: CGPoint(x: frame.midX, y: frame.midY - 90),
                      size: CGSize(width: 280, height: 76), fontSize: 30),
        ]
        readyNodes.forEach { $0.zPosition = 30 }
    }

    // MARK: - 壁と障害物

    func sideWallBody(x: CGFloat) -> SKPhysicsBody {
        let body = SKPhysicsBody(edgeFrom: CGPoint(x: x, y: 20), to: CGPoint(x: x, y: frame.maxY - 20))
        body.categoryBitMask = wallCategory
        body.restitution = wallsBouncy ? 1.0 : 0.2
        return body
    }

    /// 左右の壁を出す／消す
    func setSideWall(_ i: Int, present: Bool) {
        guard sideWallPresent[i] != present else { return }
        sideWallPresent[i] = present
        let wall = sideWalls[i]
        if present {
            wall.physicsBody = sideWallBody(x: i == 0 ? 20 : frame.maxX - 20)
            wall.alpha = 1
        } else {
            wall.physicsBody = nil
            wall.alpha = 0.1
        }
    }

    /// レベルが変わったときに、そのレベルの仕掛け（跳ねる壁・消える壁・障害物）にそろえる
    func applyLevelGimmicks() {
        // 跳ねる壁
        wallsBouncy = level.bouncyWalls
        for (i, wall) in sideWalls.enumerated() {
            wall.strokeColor = wallsBouncy ? .systemOrange : .darkGray
            wall.lineWidth = wallsBouncy ? 10 : 6
            if sideWallPresent[i] { wall.physicsBody = sideWallBody(x: i == 0 ? 20 : frame.maxX - 20) }
        }
        // 消える壁がないレベルでは、壁を必ず出しておく
        if level.wallTimes == nil {
            for i in 0..<sideWalls.count {
                setSideWall(i, present: true)
                sideWalls[i].alpha = 1
            }
        }
        // 障害物（14：跳ねない、14+：跳ねる。どちらも動かない）
        if level.bumpers == .none {
            bumpers.forEach { $0.removeFromParent() }
            bumpers = []
        } else {
            if bumpers.isEmpty {
                for x in bumperBaseX {
                    let bumper = SKShapeNode(circleOfRadius: 30)
                    bumper.lineWidth = 5
                    bumper.position = CGPoint(x: x, y: 400)
                    addChild(bumper)
                    bumpers.append(bumper)
                }
            }
            let bouncy = level.bumpers == .bouncy
            for bumper in bumpers {
                // 跳ねる障害物はオレンジ、跳ねない障害物は灰色
                bumper.fillColor = (bouncy ? UIColor.systemOrange : UIColor.gray).withAlphaComponent(0.25)
                bumper.strokeColor = bouncy ? .systemOrange : .darkGray
                let body = SKPhysicsBody(circleOfRadius: 30)
                body.isDynamic = false
                body.restitution = bouncy ? 1.0 : 0.2
                body.categoryBitMask = bouncy ? bumperCategory : 0x1 << 4   // 跳ねない障害物は弾かない
                bumper.physicsBody = body
            }
        }
    }

    /// 消える壁を進める
    func updateGimmicks(deltaTime: Double) {
        if let times = level.wallTimes {
            wallCycleTime += deltaTime
            let warn = min(SurvivalRule.wallWarnTime, times.on)
            let cycle = times.on + times.off
            for i in 0..<sideWalls.count {
                // 左右で半周期ずらす（同時には消えない）
                let t = (wallCycleTime + Double(i) * cycle / 2).truncatingRemainder(dividingBy: cycle)
                if t < times.on - warn {
                    setSideWall(i, present: true)
                    sideWalls[i].alpha = 1
                } else if t < times.on {
                    setSideWall(i, present: true)
                    sideWalls[i].alpha = 0.3 + 0.7 * CGFloat(abs(sin(t * 12)))   // もうすぐ消える合図の点滅
                } else {
                    setSideWall(i, present: false)
                }
            }
        }
    }

    // MARK: - ボール

    func makeBall(_ kind: BallKind, isLife: Bool = false) -> BallNode {
        let r = BallKind.radius
        let textures = texturesFor(kind)

        let pattern = SKSpriteNode(texture: textures.pattern)
        pattern.size = CGSize(width: r * 4, height: r * 4)
        let ball = BallNode(kind: kind, pattern: pattern)

        let shadow = SKShapeNode(circleOfRadius: r)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: r * 0.2, y: -r * 0.3)
        shadow.zPosition = -0.5
        ball.addChild(shadow)

        let crop = SKCropNode()
        let mask = SKShapeNode(circleOfRadius: r)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        crop.addChild(pattern)
        ball.addChild(crop)

        let shade = SKSpriteNode(texture: textures.shade)
        shade.size = CGSize(width: r * 2, height: r * 2)
        shade.zPosition = 1
        ball.addChild(shade)

        let shine = SKShapeNode(circleOfRadius: r * 0.2)
        shine.fillColor = UIColor.white.withAlphaComponent(0.7)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -r * 0.45, y: r * 0.45)
        shine.zPosition = 2
        ball.addChild(shine)

        let mark = SKShapeNode(path: kind.markPath(size: r * 0.42))
        mark.strokeColor = kind.markColor
        mark.lineWidth = 3
        mark.zPosition = 3
        ball.addChild(mark)

        // ハートのボール：白く光るふちと♥
        if isLife {
            ball.isLife = true
            let ring = SKShapeNode(circleOfRadius: r + 4)
            ring.strokeColor = lifeRing
            ring.lineWidth = 4
            ring.glowWidth = 2
            ring.fillColor = .clear
            ring.zPosition = 4
            ring.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.4), .scale(to: 1.0, duration: 0.4)])))
            ball.addChild(ring)
            let heart = SKLabelNode(fontNamed: "HiraginoSans-W6")
            heart.text = "♥"
            heart.fontSize = 20
            heart.fontColor = .systemPink
            heart.verticalAlignmentMode = .center
            heart.position = CGPoint(x: r * 0.9, y: r * 0.9)
            heart.zPosition = 5
            ball.addChild(heart)
        }

        let body = SKPhysicsBody(circleOfRadius: r)
        body.restitution = BallKind.restitution
        body.linearDamping = BallKind.damping
        body.density = BallKind.density
        body.friction = 0.2
        body.allowsRotation = false
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = ballCategory
        body.contactTestBitMask = lineCategory | wallCategory | bumperCategory
        ball.physicsBody = body
        return ball
    }

    func texturesFor(_ kind: BallKind) -> (pattern: SKTexture, shade: SKTexture) {
        if let cached = textureCache[kind] { return cached }
        let r = BallKind.radius

        let size = r * 4
        let period = r
        let dot = period * 0.18
        let patternImage = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            kind.color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.white.withAlphaComponent(0.35).setFill()
            var y: CGFloat = 0
            while y < size {
                var x: CGFloat = 0
                while x < size {
                    ctx.cgContext.fillEllipse(in: CGRect(x: x + period / 2 - dot, y: y + period / 2 - dot,
                                                         width: dot * 2, height: dot * 2))
                    x += period
                }
                y += period
            }
        }

        let d = r * 2
        let shadeImage = UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
            let colors = [UIColor(red: 0, green: 0, blue: 0, alpha: 0).cgColor,
                          UIColor(red: 0, green: 0, blue: 0, alpha: 0.5).cgColor] as CFArray
            let locations: [CGFloat] = [0.35, 1.0]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: locations) else { return }
            let center = CGPoint(x: d / 2, y: d / 2)
            ctx.cgContext.drawRadialGradient(gradient,
                                             startCenter: CGPoint(x: center.x - d * 0.15, y: center.y - d * 0.15),
                                             startRadius: 0, endCenter: center, endRadius: d / 2, options: [])
        }

        let result = (pattern: SKTexture(image: patternImage), shade: SKTexture(image: shadeImage))
        textureCache[kind] = result
        return result
    }

    func updateRollingLook(deltaTime: CGFloat) {
        let period = BallKind.radius
        for ball in balls {
            guard let v = ball.physicsBody?.velocity else { continue }
            var p = ball.pattern.position
            p.x = (p.x + v.dx * deltaTime).truncatingRemainder(dividingBy: period)
            p.y = (p.y + v.dy * deltaTime).truncatingRemainder(dividingBy: period)
            ball.pattern.position = p
        }
    }

    /// ボールをはじけるように消す（色が増えるとき）
    func popAllBalls() {
        for ball in balls {
            ball.physicsBody = nil
            ball.run(.sequence([
                .group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]),
                .removeFromParent(),
            ]))
        }
        balls = []
    }

    // MARK: - 投入口

    var activeSpawnerCount: Int {
        if let stage = stage { return min(maxSpawners, stage.spawnerSpeeds.count) }
        if isSurvival { return min(maxSpawners, level.colors) }   // 投入口の数＝色の数
        if isDemo { return min(maxSpawners, DemoSettings.colors) }
        return 1
    }

    /// あそびかた・ステージ用の間隔
    var currentInterval: Double {
        if let stage = stage { return stage.interval }
        if isDemo { return DemoSettings.interval }
        return tutorialSteps[tutorialIndex].interval
    }

    /// サバイバル用の間隔（最後のレベルは出すごとに短くなる）
    var survivalInterval: Double {
        guard level.intervalStep > 0 else { return level.interval }
        let steps = spawnedInLevel / max(1, level.intervalEvery)
        return max(level.minInterval, level.interval - level.intervalStep * Double(steps))
    }

    func spawnerSpeed(_ k: Int) -> Double {
        if let stage = stage { return stage.spawnerSpeeds[k % stage.spawnerSpeeds.count] }
        if isSurvival || isDemo { return SurvivalRule.spawnerSpeeds[k % SurvivalRule.spawnerSpeeds.count] }
        return 0.5
    }

    func drawNextKind() -> BallKind? {
        if !isSurvival && !isDemo { return queue.isEmpty ? nil : queue.removeFirst() }
        return kinds.randomElement()
    }

    /// 投入口 k の「次に出るボール」を決める
    func refill(_ k: Int) {
        nextKinds[k] = drawNextKind()
        nextIsLife[k] = false
        nextAngle[k] = 0
        if isDemo && nextKinds[k] != nil {
            demoDrawn += 1
            nextIsLife[k] = demoDrawn % 10 == 0   // デモではときどきハートを見せる
            return
        }
        guard isSurvival, nextKinds[k] != nil else { return }

        drawnInLevel += 1
        nextIsLife[k] = isHeart(drawnInLevel)
        nextAngle[k] = randomAngle()
    }

    /// このレベルで n 番目に出るボールをハートにするか
    /// ノルマの数までは表の位置で、それを過ぎたら heartEvery 個ごと（あと1個でレベルアップのときは出さない）
    func isHeart(_ n: Int) -> Bool {
        guard let quota = level.quota else { return false }
        if n <= quota { return level.hearts.contains(n) }
        return (n - quota) % SurvivalRule.heartEvery == 0 && correctInLevel < quota - 1
    }

    /// ななめの角度（左右はランダム。ななめのないレベルは0）
    func randomAngle() -> Double {
        guard let angle = level.angle else { return 0 }
        return Bool.random() ? angle : -angle
    }

    /// レベルが上がったとき、投入口にもう表示されている「次のボール」を
    /// 新しいレベルの1個目・2個目…として数え直す（ハートの位置がずれないように）
    func recountPreviewsForNewLevel() {
        let active = activeSpawnerCount
        for j in 0..<active {
            let k = (spawnCounter + j) % active   // 出てくる順番に数える
            guard nextKinds[k] != nil else { continue }
            drawnInLevel += 1
            nextIsLife[k] = isHeart(drawnInLevel)
            nextAngle[k] = randomAngle()
        }
    }

    /// 投入口を動かし、「次に出るボール」の表示を更新
    func updateSpawners(deltaTime: Double) {
        let active = activeSpawnerCount
        for k in 0..<maxSpawners {
            let isActive = k < active
            spawners[k].isHidden = !isActive
            guard isActive else { continue }

            if (isSurvival || isDemo) && nextKinds[k] == nil {
                refill(k)
            }

            if isTutorial, let fixedX = tutorialSteps[tutorialIndex].spawnerX {
                spawners[k].position.x = fixedX
            } else {
                spawnerAngles[k] += spawnerSpeed(k) * deltaTime
                spawners[k].position.x = frame.midX + spawnerSwing * CGFloat(cos(spawnerAngles[k]))
            }

            if let kind = nextKinds[k] {
                previews[k].isHidden = false
                previews[k].fillColor = kind.color
                previewMarks[k].path = kind.markPath(size: 6)
                previewMarks[k].strokeColor = kind.markColor
                previewHearts[k].isHidden = !nextIsLife[k]
                previewArrows[k].isHidden = nextAngle[k] == 0
                previewArrows[k].text = nextAngle[k] < 0 ? "↙" : "↘"
            } else {
                previews[k].isHidden = true
                previewHearts[k].isHidden = true
                previewArrows[k].isHidden = true
            }
        }
    }

    /// 投入口を順番に使ってボールを1つ出す
    func spawnNext() {
        let active = activeSpawnerCount
        for attempt in 0..<active {
            let k = (spawnCounter + attempt) % active
            guard let kind = nextKinds[k] else { continue }
            let ball = makeBall(kind, isLife: nextIsLife[k])
            ball.position = CGPoint(x: spawners[k].position.x, y: spawnY - 40)
            addChild(ball)
            if nextAngle[k] != 0 {
                let rad = nextAngle[k] * .pi / 180
                ball.physicsBody?.velocity = CGVector(dx: SurvivalRule.angledSpeed * CGFloat(sin(rad)),
                                                      dy: -SurvivalRule.angledSpeed * CGFloat(cos(rad)))
            } else {
                ball.physicsBody?.velocity = CGVector(dx: 0, dy: -80)
            }
            balls.append(ball)
            spawnedInLevel += 1
            refill(k)
            spawnCounter = k + 1
            return
        }
    }

    // MARK: - 進行

    func startCountdown() {
        phase = .countdown
        readyNodes.forEach { $0.removeFromParent() }
        readyNodes = []
        run(.sequence([
            .run { self.messageLabel.text = "3" }, .wait(forDuration: 0.6),
            .run { self.messageLabel.text = "2" }, .wait(forDuration: 0.6),
            .run { self.messageLabel.text = "1" }, .wait(forDuration: 0.6),
            .run { self.beginRun() },
        ]))
    }

    func beginRun() {
        phase = .run
        physicsWorld.speed = 1
        messageLabel.text = ""
        currentFlow = normalFlow
        runTime = 0
        nextSpawnTime = 1.0
        spawnTimer = 0
        if isTutorial { startTutorialStep(tutorialIndex) }
    }

    func stopPlay() {
        phase = .finished
        physicsWorld.speed = 0
        removeAction(forKey: "flash")
        messageLabel.fontColor = .darkGray
        messageDetailLabel.text = ""
    }

    // あそびかた

    func startTutorialStep(_ i: Int) {
        tutorialIndex = i
        stepPaused = false
        balls.forEach { $0.removeFromParent() }
        balls = []
        let step = tutorialSteps[i]
        queue = step.balls
        nextKinds = Array(repeating: nil, count: maxSpawners)
        nextIsLife = Array(repeating: false, count: maxSpawners)
        nextAngle = Array(repeating: 0, count: maxSpawners)
        nextKinds[0] = drawNextKind()
        nextSpawnTime = runTime + 1.5
        stepTitleLabel.text = "\(i + 1). \(step.title)"
        stepDetailLabel.text = step.detail

        hintNode?.removeFromParent()
        hintNode = nil
        if step.keepLines { clearLines() }
        if let hint = step.hint {
            let (a, b) = hint
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let container = SKNode()
            container.zPosition = 5
            if step.onlyNearHint {
                let zone = SKShapeNode(path: path)
                zone.strokeColor = lineColor.withAlphaComponent(0.12)
                zone.lineWidth = hintRadius * 2
                zone.lineCap = .round
                container.addChild(zone)
            }
            let dashed = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: [14, 10]))
            dashed.strokeColor = lineColor
            dashed.lineWidth = 6
            dashed.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
            container.addChild(dashed)
            addChild(container)
            hintNode = container
        }
        updateHUD()
    }

    func tutorialRetry() {
        stepPaused = true
        flash("おしい！もう一度やってみよう！", color: .systemRed)
        run(.sequence([.wait(forDuration: 1.3), .run { [weak self] in
            guard let self = self, self.phase == .run else { return }
            self.startTutorialStep(self.tutorialIndex)
        }]))
    }

    func tutorialStepDone() {
        stepPaused = true
        flash("OK！", color: .systemGreen)
        run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
            guard let self = self, self.phase == .run else { return }
            self.tutorialFinished()
        }]))
    }

    func tutorialFinished() {
        stopPlay()
        hintNode?.removeFromParent()
        stepTitleLabel.text = ""
        stepDetailLabel.text = ""
        messageLabel.text = ""
        let panel = makePanel()
        let isLast = tutorialIndex + 1 >= tutorialSteps.count
        panel.addLabel("お題\(tutorialIndex + 1) クリア！", at: CGPoint(x: 0, y: 90), fontSize: 40)
        panel.addLabel(isLast ? "これで遊び方はバッチリ！さっそく遊んでみよう！" : "次のお題に進んでみよう！",
                       at: CGPoint(x: 0, y: 30), fontSize: 22, bold: false)
        if isLast {
            panel.addButton("サバイバル", name: "survival", at: CGPoint(x: -120, y: -80), size: CGSize(width: 200, height: 64), fontSize: 26)
        } else {
            panel.addButton("次にすすむ", name: "nextLesson", at: CGPoint(x: -120, y: -80), size: CGSize(width: 200, height: 64), fontSize: 26)
        }
        panel.addButton("メニュー", name: "lessons", at: CGPoint(x: 120, y: -80), size: CGSize(width: 200, height: 64))
    }

    // デモプレイ（タイトルで放置されたときの自動プレイ）

    func startDemo() {
        // 下のほうに「デモプレイ中」の帯を出す
        let banner = SKShapeNode(rectOf: CGSize(width: frame.width - 40, height: 44))
        banner.fillColor = UIColor.white.withAlphaComponent(0.85)
        banner.strokeColor = .clear
        banner.position = CGPoint(x: frame.midX, y: binTop + 50)
        banner.zPosition = 40
        let text = banner.addLabel(DemoSettings.bannerText, at: .zero, fontSize: 22, color: .systemRed)
        text.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        addChild(banner)
        demoBanner = banner

        // 決まった時間がたったらタイトルへ戻る
        run(.sequence([.wait(forDuration: DemoSettings.length), .run { [weak self] in
            self?.go(to: MenuScene(size: gameSceneSize))
        }]))
        beginRun()
    }

    /// デモ：説明文の切り替え、レバーの実演、ボールに合わせて線を引く
    func updateDemo(deltaTime: Double) {
        // 説明文を順番に表示
        let captions = DemoSettings.captions
        if !captions.isEmpty {
            let index = Int(runTime / DemoSettings.captionTime) % captions.count
            if index != demoCaptionIndex {
                demoCaptionIndex = index
                stepTitleLabel.text = captions[index]
            }
            // レバーの説明の間だけ、レバーを動かして見せる
            if captions[index].contains("レバー") {
                let t = runTime.truncatingRemainder(dividingBy: DemoSettings.captionTime)
                setSpeed(t < 1.5 ? .normal : (t < 3.0 ? .fast : .slow))
            } else if flowSpeed != .normal {
                setSpeed(.normal)
            }
        }

        // ボールごとに、必要なら行き先の箱に向けて線を引く
        for ball in balls {
            guard let bin = bins.first(where: { $0.kind == ball.kind }) else { continue }
            let targetX = (bin.minX + bin.maxX) / 2
            if !ball.demoHandled && ball.position.y < 560 {
                ball.demoHandled = true
                let halfWidth = (bin.maxX - bin.minX) / 2
                if abs(targetX - ball.position.x) > halfWidth * 0.6 {
                    let dir: CGFloat = targetX > ball.position.x ? 1 : -1
                    let y0 = ball.position.y - 60
                    let points = [CGPoint(x: ball.position.x - dir * 50, y: y0 + 18),
                                  CGPoint(x: ball.position.x + dir * 40, y: y0 - 12),
                                  CGPoint(x: ball.position.x + dir * 130, y: y0 - 50)]
                    addAutoLine(points)
                }
            }
        }
    }

    /// デモ用：自動で線を引く（インクが足りなければ引かない）
    @discardableResult
    func addAutoLine(_ points: [CGPoint]) -> Bool {
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        guard inkOnScreen + length <= maxInk else { return false }
        let line = SKShapeNode()
        line.strokeColor = lineColor
        line.lineWidth = 8
        line.lineCap = .round
        line.lineJoin = .round
        addChild(line)
        lines.append(line)
        inkOnScreen += length
        updateInkBar()

        // 指で描くのと同じように、0.2秒かけて線をのばす（当たり判定も描いた分だけ）
        let drawTime: CGFloat = 0.2
        let grow = SKAction.customAction(withDuration: TimeInterval(drawTime)) { [weak self] node, elapsed in
            guard let self = self, let line = node as? SKShapeNode, elapsed > 0.01 else { return }
            let drawn = self.partialPoints(points, fraction: min(1, elapsed / drawTime))
            guard drawn.count >= 2 else { return }
            let path = self.makePath(drawn)
            line.path = path
            line.physicsBody = self.makeLineBody(path)
        }
        line.run(grow)
        line.run(.sequence([
            .wait(forDuration: TimeInterval(drawTime)),
            .wait(forDuration: lineLifetime),
            .fadeOut(withDuration: 0.3),
            .run { [weak self, weak line] in
                guard let self = self, let line = line else { return }
                line.removeFromParent()
                self.lines.removeAll { $0 === line }
                self.inkOnScreen = max(0, self.inkOnScreen - length)
                self.updateInkBar()
            },
        ]))
        return true
    }

    /// 折れ線の先頭から fraction（0〜1）の長さまでの点
    func partialPoints(_ points: [CGPoint], fraction: CGFloat) -> [CGPoint] {
        var total: CGFloat = 0
        for i in 1..<points.count { total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
        var remaining = total * fraction
        var result = [points[0]]
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if remaining >= seg {
                result.append(b)
                remaining -= seg
            } else {
                let t = seg > 0 ? remaining / seg : 0
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                break
            }
        }
        return result
    }

    // ステージ

    func stageFinished() {
        guard let i = stageIndex else { return }
        stopPlay()
        let rate = Double(correct) / Double(max(totalBalls, 1))
        let stars = rate >= 0.9 ? 3 : rate >= 0.7 ? 2 : rate >= 0.5 ? 1 : 0
        let panel = makePanel()
        panel.addLabel(stars > 0 ? "ステージ\(i + 1) クリア！" : "もうすこし！", at: CGPoint(x: 0, y: 110), fontSize: 38)
        panel.addLabel(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars),
                       at: CGPoint(x: 0, y: 50), fontSize: 48, color: .systemOrange)
        panel.addLabel("正解 \(correct) / \(totalBalls)", at: CGPoint(x: 0, y: -5), fontSize: 26)
        panel.addButton("もう一度", name: "retryStage", at: CGPoint(x: -170, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
        if i + 1 < Stages.all.count {
            panel.addButton("次へすすむ", name: "nextStage", at: CGPoint(x: 0, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
        } else {
            panel.addButton("サバイバル", name: "survival", at: CGPoint(x: 0, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
        }
        panel.addButton("ステージ一覧", name: "stages", at: CGPoint(x: 170, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
    }

    // サバイバル

    /// ノルマ達成：すぐ次のレベルへ。色が増えるときだけ画面のボールを全部消す
    func levelUp() {
        guard levelIndex + 1 < SurvivalRule.levels.count else { return }
        let old = level
        let oldColors = old.colors
        levelIndex += 1
        correctInLevel = 0
        drawnInLevel = 0
        spawnedInLevel = 0
        spawnTimer = 0
        let detail = levelChangeDescription(from: old, to: level)
        flash("レベルアップ！", color: .systemOrange, duration: detail.isEmpty ? 1.5 : 2.5, detail: detail)

        if level.colors != oldColors {
            popAllBalls()
            kinds = Array(BallKind.allCases.prefix(level.colors))
            bins = makeBins()
            buildBins()
            nextKinds = Array(repeating: nil, count: maxSpawners)
            nextIsLife = Array(repeating: false, count: maxSpawners)
            nextAngle = Array(repeating: 0, count: maxSpawners)
            spawnCounter = 0   // 1番目の投入口から順に出す（ハートの順番がずれないように）
            spawnBlockedUntil = runTime + 1.0   // 色が増えた直後は1秒待ってからボールを出す
        } else {
            recountPreviewsForNewLevel()
        }
        applyLevelGimmicks()
        updateHUD()
    }

    /// レベルアップで色やギミックが変わるときの説明（変わらなければ空）
    func levelChangeDescription(from old: SurvivalLevel, to new: SurvivalLevel) -> String {
        var notes: [String] = []
        if new.colors > old.colors {
            let added = BallKind.allCases.prefix(new.colors).dropFirst(old.colors).map { $0.label }.joined(separator: "・")
            notes.append("\(added)が増えたよ！")
        }
        switch (old.angle, new.angle) {
        case (nil, .some):
            notes.append("ボールが斜めに出てくるよ！")
        case let (.some(a), .some(b)) where b > a:
            notes.append("")
        default: break
        }
        if new.bouncyWalls && !old.bouncyWalls {
            notes.append("左右の壁が跳ねるようになったよ！")
        }
        switch (old.wallTimes, new.wallTimes) {
        case (nil, .some):
            notes.append("左右の壁がときどき消えるようになったよ！外に出ないように気をつけよう！")
        case let (.some(a), .some(b)) where b.off > a.off:
            notes.append("")
        default: break
        }
        if old.bumpers == .none && new.bumpers == .bouncy {
            notes.append("跳ねる障害物が出現！")
        } else if old.bumpers == .none && new.bumpers == .solid {
            notes.append("障害物が出現！")
        } else if old.bumpers == .solid && new.bumpers == .bouncy {
            notes.append("障害物が跳ねるようになったよ！")
        }
        let hadGimmicks = old.angle != nil || old.bouncyWalls || old.wallTimes != nil || old.bumpers != .none
        let hasGimmicks = new.angle != nil || new.bouncyWalls || new.wallTimes != nil || new.bumpers != .none
        if hadGimmicks && !hasGimmicks {
            notes.append("ボールの数はだんだん増えるよ！どこまで上を目指せるかな？")
        }
        return notes.filter { !$0.isEmpty }.joined(separator: "\n")   // 1つの変化を1行で（空の説明は出さない）
    }

    func gameOver() {
        stopPlay()
        let score = correct
        let levelName = level.name
        messageLabel.text = "ゲームオーバー　Lv\(levelName)　スコア \(score)"
        if SaveData.qualifies(score) && !devMode {
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
                self?.askName(score: score) { name in
                    let rank = SaveData.addRanking(name: name, score: score, level: levelName)
                    self?.go(to: RankingScene(size: gameSceneSize, highlight: rank))
                }
            }]))
        } else {
            messageLabel.text = ""
            let panel = makePanel()
            panel.addLabel("ゲームオーバー", at: CGPoint(x: 0, y: 100), fontSize: 40)
            panel.addLabel("Lv\(levelName)　スコア \(score)", at: CGPoint(x: 0, y: 30), fontSize: 36, color: .systemOrange)
            panel.addButton("もう一度あそぶ", name: "survival", at: CGPoint(x: -170, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
            panel.addButton("ランキング", name: "ranking", at: CGPoint(x: 0, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
            panel.addButton("メニュー", name: "menu", at: CGPoint(x: 170, y: -95), size: CGSize(width: 164, height: 60), fontSize: 20)
        }
    }

    func makePanel() -> SKShapeNode {
        let panel = SKShapeNode(rectOf: CGSize(width: 560, height: 320), cornerRadius: 24)
        panel.fillColor = UIColor.white.withAlphaComponent(0.96)
        panel.strokeColor = .darkGray
        panel.lineWidth = 3
        panel.position = CGPoint(x: frame.midX, y: frame.midY + 40)
        panel.zPosition = 50
        addChild(panel)
        return panel
    }

    func askName(score: Int, completion: @escaping (String) -> Void) {
        guard let vc = topViewController() else { completion("名もなきプレイヤー"); return }
        let alert = UIAlertController(title: "ランクイン！", message: "スコア \(score)\n名前を入れてください", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "なまえ（15文字まで）" }
        alert.addAction(UIAlertAction(title: "登録", style: .default) { _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            completion(text.isEmpty ? "名もなきプレイヤー" : String(text.prefix(15)))
        })
        vc.present(alert, animated: true)
    }

    // MARK: - 毎フレームの処理

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 0.05)
        lastUpdateTime = currentTime
        updateRollingLook(deltaTime: CGFloat(deltaTime))

        guard phase == .run else { return }
        runTime += deltaTime

        // 流れの速さ（レバー）
        var target: CGFloat
        switch flowSpeed {
        case .slow:   target = slowFlow
        case .normal: target = normalFlow
        case .fast:   target = fastFlow
        }
        if isSurvival { target *= level.flowScale }
        if let stage = stage { target *= stage.flowScale }
        currentFlow += (target - currentFlow) * min(1, CGFloat(deltaTime) * 6)
        physicsWorld.gravity = CGVector(dx: 0, dy: -currentFlow)

        // 投入口とボールを出す
        updateSpawners(deltaTime: deltaTime)
        if isSurvival {
            // 同時出現数の上限に達したらタイマーを止め、下回ったら0から数え直す
            if balls.count >= (level.maxOnScreen ?? Int.max) {
                spawnTimer = 0
            } else {
                spawnTimer += deltaTime
                // 色が増えた直後は、間隔が短くても最低1秒は待つ（間隔が1秒より長ければ、待ち時間は変わらない）
                if spawnTimer >= survivalInterval && runTime >= spawnBlockedUntil {
                    spawnNext()
                    spawnTimer = 0
                }
            }
            updateGimmicks(deltaTime: deltaTime)
        } else if !(isTutorial && stepPaused) && !waitingForLine && runTime >= nextSpawnTime {
            spawnNext()
            nextSpawnTime = runTime + currentInterval
        }

        // 箱に入ったかの判定
        for ball in balls where ball.position.y < scoreLine {
            guard balls.contains(where: { $0 === ball }) else { continue }   // レベルアップで消えたボールは数えない
            guard let bin = bins.first(where: { ball.position.x >= $0.minX && ball.position.x < $0.maxX }) else { continue }
            let success = bin.kind == ball.kind
            if success { correct += 1 } else { wrong += 1 }
            collect(ball, success: success)

            if isTutorial && !success && !stepPaused {
                tutorialRetry()
            }
            if isSurvival {
                if !success {
                    loseLife("ミス！")
                } else {
                    correctInLevel += 1
                    if ball.isLife && lives < SurvivalRule.maxLives {
                        lives += 1
                        flash("♥+1！", color: .systemPink)
                    }
                    if let quota = level.quota, correctInLevel >= quota {
                        levelUp()
                    }
                }
            }
        }

        if isDemo { updateDemo(deltaTime: deltaTime) }

        // どこかに引っかかって止まったボールは、軽く押して動かす
        for ball in balls {
            guard let body = ball.physicsBody else { continue }
            if hypot(body.velocity.dx, body.velocity.dy) < 8 {
                ball.stillTime += deltaTime
                if ball.stillTime > 1.5 {
                    body.velocity = CGVector(dx: Bool.random() ? 120 : -120, dy: 0)
                    ball.stillTime = 0
                }
            } else {
                ball.stillTime = 0
            }
        }

        // 場外に出たボールはミス
        let r = BallKind.radius
        for ball in balls where ball.position.x < 20 - r || ball.position.x > frame.maxX - 20 + r {
            balls.removeAll { $0 === ball }
            ball.physicsBody = nil
            ball.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            wrong += 1
            if isSurvival {
                loseLife("コースアウト！")
            } else if isTutorial && !stepPaused {
                tutorialRetry()
            }
        }
        updateHUD()

        // 終了・クリアの判定
        if isSurvival {
            // ライフがなくなったか、ボールがたまりすぎたら終了
            if lives <= 0 || balls.count > SurvivalRule.maxBallsOnScreen { gameOver(); return }
        } else if isDemo {
            // デモは終わらない（時間がきたらタイトルへ戻る）
        } else if isTutorial {
            if !stepPaused && queue.isEmpty && nextKinds.allSatisfy({ $0 == nil }) && balls.isEmpty {
                tutorialStepDone()
            }
        } else if queue.isEmpty && nextKinds.allSatisfy({ $0 == nil }) {
            if balls.isEmpty || runTime > nextSpawnTime + 10 {
                stageFinished()
            }
        }
    }

    /// ミスや場外でライフを1つ減らす（開発者モードの無敵中は減らない）
    func loseLife(_ message: String) {
        if !(devMode && DevSettings.invincible) { lives -= 1 }
        if lives > 0 { flash(message, color: .systemRed) }
    }

    func collect(_ ball: BallNode, success: Bool) {
        balls.removeAll { $0 === ball }
        ball.physicsBody = nil
        let mark = SKLabelNode(fontNamed: "HiraginoSans-W6")
        mark.text = success ? "○" : "×"
        mark.fontSize = 34
        mark.fontColor = success ? .systemGreen : .systemRed
        mark.position = CGPoint(x: ball.position.x, y: binTop + 10)
        mark.zPosition = 5
        addChild(mark)
        mark.run(.sequence([.group([.moveBy(x: 0, y: 30, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        ball.run(.sequence([.group([.scale(to: 0.1, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }

    func flash(_ text: String, color: UIColor, duration: Double = 0.9, detail: String = "") {
        messageLabel.text = text
        messageLabel.fontColor = color
        messageDetailLabel.text = detail
        run(.sequence([.wait(forDuration: duration), .run { [weak self] in
            guard let self = self, self.phase == .run else { return }
            self.messageLabel.text = ""
            self.messageLabel.fontColor = .darkGray
            self.messageDetailLabel.text = ""
        }]), withKey: "flash")
    }

    // MARK: - 表示の更新

    func updateHUD() {
        if isSurvival {
            scoreLabel.text = "Lv\(level.name)　スコア \(correct)"
            for (i, slot) in lifeSlots.enumerated() {
                let filled = i < lives
                slot.text = filled ? "♥" : "♡"
                slot.fontColor = filled || i < SurvivalRule.lives ? .systemRed : .lightGray
            }
            updateLevelBar()
        } else if let i = stageIndex {
            let waiting = queue.count + nextKinds.compactMap { $0 }.count
            scoreLabel.text = "ステージ\(i + 1)　正解 \(correct)　ミス \(wrong)　残り \(waiting + balls.count)"
        } else if isDemo {
            scoreLabel.text = ""
        } else {
            scoreLabel.text = "あそびかた　お題\(tutorialIndex + 1)"
        }
    }

    /// 次のレベルまでのメーター（ノルマに対して今いくつ正解したか）
    func updateLevelBar() {
        guard let label = levelBarLabel else { return }
        guard let quota = level.quota else {
            // 最後のレベル（ノルマなし）は、文字を出さずにメーターを満タンにしておく
            label.text = ""
            levelBarFill.path = CGPath(roundedRect: levelBarRect, cornerWidth: 7, cornerHeight: 7, transform: nil)
            return
        }
        let remaining = max(0, quota - correctInLevel)
        label.text = "次のレベルまで あと\(remaining)"
        let ratio = min(1, CGFloat(correctInLevel) / CGFloat(max(quota, 1)))
        if ratio <= 0 {
            levelBarFill.path = nil
        } else {
            let width = max(2, levelBarRect.width * ratio)
            let corner = min(7, width / 2)
            levelBarFill.path = CGPath(roundedRect: CGRect(x: levelBarRect.minX, y: levelBarRect.minY,
                                                           width: width, height: levelBarRect.height),
                                       cornerWidth: corner, cornerHeight: corner, transform: nil)
        }
    }

    func updateInkBar() {
        let ratio = max(0, 1 - inkOnScreen / maxInk)
        let width = max(2, 220 * ratio)
        let corner = min(8, width / 2)
        inkBar.path = CGPath(roundedRect: CGRect(x: 40, y: frame.maxY - 72, width: width, height: 16),
                             cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    // MARK: - やめるときの確認

    func confirmQuit() {
        let destination: SKScene
        if isTutorial {
            destination = TutorialSelectScene(size: gameSceneSize)
        } else if stage != nil {
            destination = StageSelectScene(size: gameSceneSize)
        } else {
            destination = MenuScene(size: gameSceneSize)
        }
        guard let vc = topViewController() else { go(to: destination); return }

        view?.isPaused = true
        let message = isSurvival ? "ここまでのスコアはランキングに記録されません" : "途中の結果は残りません"
        let alert = UIAlertController(title: "やめますか？", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "つづける", style: .cancel) { [weak self] _ in
            self?.view?.isPaused = false
        })
        alert.addAction(UIAlertAction(title: "やめる", style: .destructive) { [weak self] _ in
            self?.view?.isPaused = false
            self?.go(to: destination)
        })
        vc.present(alert, animated: true)
    }

    // MARK: - タッチ（ボタン・レバー・線引き）。複数の指を同時に使える

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // デモ中は、どこを触ってもタイトルへ戻る
        if isDemo {
            go(to: MenuScene(size: gameSceneSize))
            return
        }
        for touch in touches {
            let point = touch.location(in: self)

            // ボタン
            if let name = buttonName(at: point), handleButton(name) { return }

            // レバー
            if leverRect.contains(point) {
                leverTouch = touch
                setSpeed(atX: point.x)
                continue
            }

            // 線を引き始める（線は1本ずつ）
            guard drawingTouch == nil, phase == .run, inkOnScreen < maxInk else { continue }
            if isTutorial && !tutorialSteps[tutorialIndex].allowDrawing { continue }
            if !isNearHint(point) { continue }
            drawingTouch = touch
            currentPoints = [point]
            currentLength = 0
            let line = SKShapeNode()
            line.strokeColor = lineColor
            line.lineWidth = 8
            line.lineCap = .round
            line.lineJoin = .round
            addChild(line)
            currentLine = line
        }
    }

    /// ボタンの処理。処理したら true
    func handleButton(_ name: String) -> Bool {
        switch name {
        case "start" where phase == .ready:
            startCountdown()
        case "quit":
            confirmQuit()
        case "lessons":
            go(to: TutorialSelectScene(size: gameSceneSize))
        case "stages":
            go(to: StageSelectScene(size: gameSceneSize))
        case "retryStage":
            go(to: GameScene(size: gameSceneSize, mode: mode))
        case "nextStage":
            if let i = stageIndex { go(to: GameScene(size: gameSceneSize, mode: .stage(i + 1))) }
        case "menu":
            go(to: MenuScene(size: gameSceneSize))
        case "nextLesson":
            go(to: GameScene(size: gameSceneSize, mode: .tutorial(tutorialIndex + 1)))
        case "survival":
            go(to: GameScene(size: gameSceneSize, mode: .survival))
        case "ranking":
            go(to: RankingScene(size: gameSceneSize, highlight: nil))
        default:
            return false
        }
        return true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if touch === leverTouch {
                setSpeed(atX: point.x)
                continue
            }
            guard touch === drawingTouch, phase == .run,
                  let line = currentLine, let last = currentPoints.last else { continue }
            guard !leverRect.contains(point), isNearHint(point) else { continue }   // レバーの上と範囲外は描かない
            let length = hypot(point.x - last.x, point.y - last.y)
            guard length > 6, inkOnScreen + length <= maxInk else { continue }

            currentPoints.append(point)
            currentLength += length
            inkOnScreen += length
            let path = makePath(currentPoints)
            line.path = path
            line.physicsBody = makeLineBody(path)
            updateInkBar()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { endTouches(touches) }

    func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === leverTouch { leverTouch = nil }
            if touch === drawingTouch {
                drawingTouch = nil
                finishLine()
            }
        }
    }

    func finishLine() {
        guard let line = currentLine else { return }
        currentLine = nil
        currentPoints = []
        guard currentLength > 0 else { line.removeFromParent(); return }

        lines.append(line)
        if isTutorial && tutorialSteps[tutorialIndex].waitForLine {
            nextSpawnTime = max(nextSpawnTime, runTime + 0.8)
        }
        if isTutorial && tutorialSteps[tutorialIndex].keepLines { return }
        let length = currentLength
        line.run(.sequence([
            .wait(forDuration: lineLifetime),
            .fadeOut(withDuration: 0.3),
            .run { [weak self, weak line] in
                guard let self = self, let line = line else { return }
                line.removeFromParent()
                self.lines.removeAll { $0 === line }
                self.inkOnScreen = max(0, self.inkOnScreen - length)
                self.updateInkBar()
            },
        ]))
    }

    /// 線を引き終わるまでボールを待たせるお題で、まだ線がないとき
    var waitingForLine: Bool {
        isTutorial && tutorialSteps[tutorialIndex].waitForLine && lines.isEmpty
    }

    /// 「点線のまわりだけ描ける」お題で、その点が描いてよい範囲にあるか
    func isNearHint(_ p: CGPoint) -> Bool {
        guard isTutorial else { return true }
        let step = tutorialSteps[tutorialIndex]
        guard step.onlyNearHint, let hint = step.hint else { return true }
        let (a, b) = hint
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        let nearest = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - nearest.x, p.y - nearest.y) <= hintRadius
    }

    func clearLines() {
        currentLine?.removeFromParent()
        currentLine = nil
        drawingTouch = nil
        currentPoints = []
        lines.forEach { $0.removeFromParent() }
        lines = []
        inkOnScreen = 0
        updateInkBar()
    }

    func makePath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    func makeLineBody(_ path: CGPath) -> SKPhysicsBody {
        let body = SKPhysicsBody(edgeChainFrom: path)
        body.restitution = lineBounce
        body.categoryBitMask = lineCategory
        return body
    }

    // MARK: - 線・跳ねる壁・障害物に当たったボールを弾く

    func didBegin(_ contact: SKPhysicsContact) {
        let ballNode = (contact.bodyA.node as? BallNode) ?? (contact.bodyB.node as? BallNode)
        let other = contact.bodyA.node is BallNode ? contact.bodyB : contact.bodyA
        guard let ball = ballNode, let body = ball.physicsBody else { return }

        let kick: CGFloat
        switch other.categoryBitMask {
        case lineCategory:                   kick = lineKick
        case wallCategory where wallsBouncy: kick = wallKick
        case bumperCategory:                 kick = bumperKick
        default: return
        }
        guard runTime - ball.lastKickTime > 0.15 else { return }
        ball.lastKickTime = runTime

        var dx = ball.position.x - contact.contactPoint.x
        var dy = ball.position.y - contact.contactPoint.y
        let length = max(hypot(dx, dy), 0.001)
        dx /= length
        dy /= length
        body.velocity = CGVector(dx: body.velocity.dx + dx * kick, dy: body.velocity.dy + dy * kick)

        if let node = other.node as? SKShapeNode {
            node.run(.sequence([.run { node.glowWidth = 6 }, .wait(forDuration: 0.1), .run { node.glowWidth = 0 }]))
        }
    }
}
