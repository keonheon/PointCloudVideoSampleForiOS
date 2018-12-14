//
//  GameViewController.swift
//  PointCloudSample
//
//  Created by Kyonhon Shin on 2018/12/14.
//  Copyright © 2018 Piecenote. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit
import AVFoundation
import CoreMotion

class ViewController: UIViewController, SCNPhysicsContactDelegate {

    let motionManager = CMMotionManager()
    let program = SCNProgram()

    struct BoxInfo {
        let step: Int
        let x: CGFloat
        let y: CGFloat
        let z: CGFloat
        let column: Int
        let row: Int
    }

    enum CollisionBitmask: Int {
        case box = 1
        case floor = 2
    }

    @IBOutlet weak var sceneView: SCNView!
    @IBOutlet weak var leftImageView: UIImageView!
    @IBOutlet weak var rightImageView: UIImageView!

    var audioPlayer: AVAudioPlayer!

    var scene: SCNScene!
    let cameraNode = SCNNode()
    let videoNode = SCNNode()
    let worldNode = SCNNode()
    var headRayNode = SCNNode()
    var infosWithStep: [[BoxInfo]] = []
    var materialsWithStep: [[SCNMaterial]] = []

    let kinectFPS: Double = 30
    var videoMaximumValue: Float = 0
    let resolutionRatio = 2

    var gazeCount = 0
    var gazedPosition = SCNVector3Zero
    let headRayNodeDefaultVector3 = SCNVector3(x: -0.03, y: -3.5, z: 3.3)
    var pointOfViewDefaultPosition: SCNVector3!


    override func viewDidLoad() {
        UIApplication.shared.isIdleTimerDisabled = true
        super.viewDidLoad()

        scene = SCNScene()
        scene.physicsWorld.contactDelegate = self
        setupCameraAndWorld()
        setupHeadTracking()
        setupView()
        setupStage()
        setupLight()

        setupAudio()
        loadFile()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { (_) in
            self.forwardMovie()
        }
        timer.fire()
        audioPlayer.play()

        setupMotionManager()
        setupGazeTimer()

        pointOfViewDefaultPosition = sceneView.pointOfView!.position
    }

    func setupGazeTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (_) in
            self.gazeCount += 1
        }
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor.green
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didUpdate contact: SCNPhysicsContact) {
        contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor.green
        if contact.nodeB.position.x != gazedPosition.x || contact.nodeB.position.y != gazedPosition.y || contact.nodeB.position.z != gazedPosition.z {

            contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor.white
            gazedPosition = contact.nodeB.position
            gazeCount = 0
        } else if gazeCount > 0 {
            if gazeCount < 2 {
                contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0, green: 200/255, blue: 0, alpha: 1)
            } else if gazeCount < 4 {
                contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0, green: 150/255, blue: 0, alpha: 1)
            } else {
                contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor.white
                positionMove(position: gazedPosition)
                gazeCount = 0
            }
        }
    }

    func positionMove(position: SCNVector3) {
        sceneView.pointOfView?.position.x = position.x - 9 + pointOfViewDefaultPosition.x // - 9 is Calibration
        sceneView.pointOfView?.position.y = position.y - 9 + pointOfViewDefaultPosition.y + 3.5 // 3.5 & - 9 are Calibration
        headRayNode.position.x = position.x - 9 + headRayNodeDefaultVector3.x // - 9 is Calibration
        headRayNode.position.y = position.y - 9 + headRayNodeDefaultVector3.y + 3.5 // 3.5 & -9 are Calibration
    }

    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        contact.nodeB.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        gazeCount = 0
    }

    func setupHeadTracking() {
        let aBoxGeometry = SCNBox(width: 0.005, height: 0.005, length: 20, chamferRadius: 0)
        let color = UIColor(red: 55/255, green: 255/255, blue: 50/255, alpha: 0.8)
        aBoxGeometry.firstMaterial?.diffuse.contents = color
        headRayNode.geometry = aBoxGeometry
        headRayNode.position = headRayNodeDefaultVector3

        // 衝突判定
        let physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        physicsBody.categoryBitMask = CollisionBitmask.box.rawValue
        physicsBody.collisionBitMask = 0
        physicsBody.contactTestBitMask = CollisionBitmask.box.rawValue
        physicsBody.isAffectedByGravity = false
        headRayNode.physicsBody = physicsBody

        worldNode.addChildNode(headRayNode)
    }

    func addNodeToVideoNode(frame: Int) {
        var infos = infosWithStep[frame]
        var materials = materialsWithStep[frame]
        if infos.count == 0 {
            infos = infosWithStep[0]
            materials = materialsWithStep[0]
        }

        var verticesArray: [SCNVector3] = []
        var faces: [SCNGeometryElement] = []
        for (index, info) in infos.enumerated() {
            let vector3s = vector3sFrom(boxInfo: info)
            for vector3 in vector3s {
                verticesArray.append(vector3)
            }

            faces.append(faceFrom(index: index))
        }

        let node = nodeFrom(verticesArray: verticesArray, faces: faces, materials: materials)
        videoNode.addChildNode(node)
    }

    func setupLight() {
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 0, z: 5)
        worldNode.addChildNode(lightNode)

        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        worldNode.addChildNode(ambientLightNode)
    }

    func setupStage() {
        let stageNode = SCNNode()
        stageNode.position = SCNVector3(x: -9, y: -9, z: 0)

        for yIndex in 0..<18 {
            for xIndex in 0..<18 {
                let aBoxGeometry = SCNBox(width: 0.99, height: 0.99, length: 0.00001, chamferRadius: 0)
                aBoxGeometry.firstMaterial?.diffuse.contents = UIColor.white
                let aBoxNode = SCNNode(geometry: aBoxGeometry)
                aBoxNode.position = SCNVector3(x: Float(xIndex), y: Float(yIndex), z: 0)

                let physicsBody = SCNPhysicsBody(type: .static, shape: nil)
                physicsBody.contactTestBitMask = CollisionBitmask.box.rawValue
                physicsBody.collisionBitMask = 0
                physicsBody.categoryBitMask = CollisionBitmask.floor.rawValue
                physicsBody.isAffectedByGravity = false
                aBoxNode.physicsBody = physicsBody

                stageNode.addChildNode(aBoxNode)
            }
        }

        stageNode.eulerAngles = SCNVector3(x: 0, y: 0, z: 0)
        worldNode.addChildNode(stageNode)
    }

    func setupMotionManager() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1
            let deviceMotionQueue = OperationQueue.init()
            motionManager.startDeviceMotionUpdates(to: deviceMotionQueue) { (deviceMotion: CMDeviceMotion?, error: Error?) in
                self.updateMotion(deviceMotion: deviceMotion, error: error)
            }
        }
    }

    func setupAudio() {
        if let path = Bundle.main.path(forResource: "something", ofType: "wav") {
            let audioURL = URL(fileURLWithPath: path)
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer.numberOfLoops = -1
                audioPlayer.prepareToPlay()
                print("Audio Loaded")
            } catch {
                print("Audio Error")
            }
        }
    }

    func setupCameraAndWorld() {
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(worldNode)
        worldNode.addChildNode(videoNode)

        // Optimize for recorded video data.
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 1)
        worldNode.position = SCNVector3(x: 2.4, y: 5, z: -1)
        videoNode.position = SCNVector3(x: 0, y: 0, z: 0)
        videoNode.eulerAngles = SCNVector3(x: 2.2, y: 0, z: 0)
    }

    func setupView() {
        sceneView.scene = scene
        sceneView.allowsCameraControl = true
        sceneView.showsStatistics = false
        sceneView.backgroundColor = UIColor.black
    }

    var prevValue = 0
}

extension ViewController {

    func forwardMovie() {
        var currentStepCount = 0

        if (!audioPlayer.isPlaying) {
            return
        }

        if (prevValue < Int(videoMaximumValue)) {
            currentStepCount = Int(audioPlayer.currentTime * kinectFPS)
        } else {
            audioPlayer.currentTime = 0
        }

        if (prevValue == currentStepCount) {
            return
        }
        prevValue = currentStepCount

        stepMovie(preferredStepCount: prevValue)
        refreshImageViews()
    }

    func refreshImageViews() {
        DispatchQueue.main.async {
            let image = self.sceneView.snapshot()
            self.rightImageView.image = image
            self.leftImageView.image = image
        }
    }

    func stepMovie(preferredStepCount: Int) {
        if preferredStepCount >= infosWithStep.count {
            return
        }

        for childNode in videoNode.childNodes {
            childNode.removeFromParentNode()
        }

        addNodeToVideoNode(frame: preferredStepCount)
    }


    func loadFile() {
        if let path = Bundle.main.path(forResource: "depth_video_data", ofType: "csv") {
            do {
                let contentString = try String(contentsOfFile: path, encoding: .utf8)
                let contentArray = contentString.components(separatedBy: .newlines)
                var prevStep = 0

                var boxInfos: [BoxInfo] = []
                var materials: [SCNMaterial] = []

                for (line, content) in contentArray.enumerated() {
                    let info = content.components(separatedBy: ",")

                    guard let step = Int(info[0]) else {
                        break
                    }

                    if prevStep < step {
                        infosWithStep.append(boxInfos)
                        materialsWithStep.append(materials)

                        boxInfos = []
                        materials = []
                    }
                    prevStep = step

                    // Down Resolution For Memory
                    let column = Int(info[7])!
                    let row = Int(info[8])!
                    if column / 4 % resolutionRatio != 0 || row / 4 % resolutionRatio != 0 {
                        continue
                    }

                    // FOR DEBUG: down size for debug rapidly
                    if step == 50 {
                        break
                    }

                    let xBase = CGFloat(Double(info[4])!)
                    let yBase = CGFloat(Double(info[5])!)

                    // Triming For Memory
                    let trimLimit: CGFloat = 400
                    if (xBase > trimLimit || yBase > trimLimit || xBase < -trimLimit || yBase < -trimLimit) {
                        continue
                    }

                    let x = xBase / 200
                    let y = yBase / 200
                    let z = CGFloat(Double(info[6])!) / 200

                    let boxInfo = BoxInfo(step: step, x: x, y: y, z: -z, column: column, row: row)
                    boxInfos.append(boxInfo)

                    var red = CGFloat(Double(info[1])!)
                    var green = CGFloat(Double(info[2])!)
                    var blue = CGFloat(Double(info[3])!)
                    if (red < 200) {
                        red += 50
                    }
                    if (green < 200) {
                        green += 50
                    }
                    if (blue < 200) {
                        blue += 50
                    }
                    let color = UIColor(red: red/255, green: green/255, blue: blue/255, alpha: 1)
                    let material = SCNMaterial()
                    material.diffuse.contents = color
                    materials.append(material)

                    print("Added: \(line)/\(contentArray.count)")
                }

                // Add Last Infos
                infosWithStep.append(boxInfos)
                materialsWithStep.append(materials)

                videoMaximumValue = Float(prevStep)

                print("Loaded File")
            } catch let error {
                print(error)
            }
        } else {
            print("Failed to load File")
        }
    }


    func nodeFrom(verticesArray: [SCNVector3], faces: [SCNGeometryElement], materials: [SCNMaterial]) -> SCNNode {
        let vertices = SCNGeometrySource(vertices: verticesArray)
        let geometry = SCNGeometry(sources: [vertices], elements: faces)
        geometry.materials = materials

        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3Zero
        return node
    }

    func vector3sFrom(boxInfo: BoxInfo) -> [SCNVector3] {
        let surfaceDiff: CGFloat = 0.05 * CGFloat(resolutionRatio)
        var vector3s: [SCNVector3] = []
        vector3s.append(SCNVector3(boxInfo.x, boxInfo.y, boxInfo.z)) // Left Top
        vector3s.append(SCNVector3(boxInfo.x+surfaceDiff, boxInfo.y, boxInfo.z)) // Right Top
        vector3s.append(SCNVector3(boxInfo.x, boxInfo.y+surfaceDiff, boxInfo.z)) // Left Bottom
        vector3s.append(SCNVector3(boxInfo.x+surfaceDiff, boxInfo.y+surfaceDiff, boxInfo.z)) // Right Bottom
        return vector3s
    }

    func faceFrom(index: Int) -> SCNGeometryElement {
        var indicesArray: [Int32] = []
        indicesArray.append(Int32(index+1+index*3))
        indicesArray.append(Int32(index+2+index*3))
        indicesArray.append(Int32(index+index*3))
        indicesArray.append(Int32(index+3+index*3))
        indicesArray.append(Int32(index+2+index*3))
        indicesArray.append(Int32(index+1+index*3))
        let face = SCNGeometryElement(indices: indicesArray, primitiveType: .triangles)
        return face
    }
}

extension ViewController {
    func updateMotion(deviceMotion: CMDeviceMotion?, error: Error?) {
        if let error = error {
            print(error)
            return
        }

        guard let deviceMotion = deviceMotion else {
            print("accelData is nil")
            return
        }

        updateSceneView(attitude: deviceMotion.attitude)
    }

    func updateSceneView(attitude: CMAttitude) {
        if let point = sceneView.pointOfView {
            point.eulerAngles.x = -Float(attitude.roll)
            point.eulerAngles.y = Float(attitude.pitch)
            point.eulerAngles.z = Float(attitude.yaw)

            headRayNode.eulerAngles = point.eulerAngles
        }
    }
}
