//
//  ViewController.swift
//  maskImage
//
//  Created by Apple  on 05/12/24.
//

import UIKit
import ARKit

class ViewController: UIViewController,ARSCNViewDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    private var metalView: MetalSineWaveView?
    
    private var maskNode: SCNNode?
    
    // Create a label to display the slider value
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.text = "Value: 0"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 18)
        return label
    }()

    // Create the slider
    private let slider: UISlider = {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 10
        slider.value = 0
        slider.isContinuous = true
        return slider
    }()
    
    // Layout configuration
    private func setupLayout() {
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        slider.translatesAutoresizingMaskIntoConstraints = false

        // Add constraints
        NSLayoutConstraint.activate([
            // Center the label horizontally and position it at the top
            valueLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            valueLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            
            // Center the slider horizontally and place it below the label
            slider.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            slider.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 20),
            slider.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8) // Make slider width 80% of the view
        ])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up the scene
        sceneView.delegate = self
        sceneView.session = ARSession()
        sceneView.scene = SCNScene()

        // Start image tracking
        guard let referenceImages = ARReferenceImage.referenceImages(
            inGroupNamed: "ImageForAR", bundle: nil) else {
                print("No reference images found.")
                return
        }
        let rootImages = [
            "0", "1", "2", "2_1", "3", "4"
        ]
        var imageSet: [String: UIImage] = [:]
        
        for imageName in rootImages {
            if let image = UIImage(named: imageName) {
                print("Found image: \(imageName)")
                imageSet[imageName] = image
            } else {
                print("Missing image: \(imageName)")
            }
        }
        
        let configuration = ARImageTrackingConfiguration()
        configuration.trackingImages = referenceImages
        configuration.maximumNumberOfTrackedImages = 1

        sceneView.session.run(configuration)
        
        if let metalView = MetalSineWaveView(frame: view.bounds, imageSet: imageSet) {
            self.metalView = metalView
            
        }
        // Add subviews
        view.addSubview(valueLabel)
        view.addSubview(slider)
        
        // Configure layout
        setupLayout()
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
    }
    
        
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }

        let referenceImage = imageAnchor.referenceImage
        let width = referenceImage.physicalSize.width
        let height = referenceImage.physicalSize.height

        // Create the main wider plane
        let plane = SCNPlane(width: width * 1.5, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = metalView
        material.isDoubleSided = true
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.geometry?.materials = [material]
        planeNode.eulerAngles.x = -.pi / 2
        
        let node = SCNNode()
        node.addChildNode(planeNode)
                
        return node
    }
    
    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let cameraNode = renderer.pointOfView {
            let angles = calculateRelativeAngles(from: cameraNode, to: node)
            print("Relative angles (radians):")
            print("X-axis: \(angles.x), Y-axis: \(angles.y), Z-axis: \(angles.z)")
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    // Handle slider value change
    @objc private func sliderValueChanged(_ sender: UISlider) {
        // Update the label text with the slider value, rounded to 1 decimal
        let currentValue = round(sender.value * 10) / 10
        valueLabel.text = "Value: \(currentValue)"
        metalView?.value = sender.value
    }
    
    func calculateRelativeAngle(from camera: SCNNode, to node: SCNNode) -> Float {
        // 1. Get the world positions of the camera and the node
        let cameraPosition = camera.worldPosition
        let nodePosition = node.worldPosition
        
        // 2. Calculate the vector from the camera to the node
        let relativeVector = SCNVector3(
            nodePosition.x - cameraPosition.x,
            nodePosition.y - cameraPosition.y,
            nodePosition.z - cameraPosition.z
        )
        
        // 3. Normalize the relative vector
        let normalizedRelativeVector = relativeVector.normalized()
        
        // 4. Get the camera's forward direction vector (negative Z-axis in its local space)
        let cameraForward = SCNVector3(-camera.worldTransform.m31,
                                       -camera.worldTransform.m32,
                                       -camera.worldTransform.m33).normalized()
        
        // 5. Calculate the dot product
        let dotProduct = cameraForward.dotProduct(with: normalizedRelativeVector)
        
        // 6. Use arccos to calculate the angle in radians
        let angleInRadians = acos(dotProduct)
        
        // 7. Optional: Calculate the cross product to determine direction
        // Cross product determines if the node is to the left or right of the camera
        let crossProduct = cameraForward.crossProduct(with: normalizedRelativeVector)
        let direction = crossProduct.y >= 0 ? 1 : -1 // +1 = right, -1 = left

        return angleInRadians * Float(direction) // Return the signed angle
    }
    
    func calculateRelativeAngles(from camera: SCNNode, to node: SCNNode) -> (x: Float, y: Float, z: Float) {
        // 1. Get world positions
        let cameraPosition = camera.worldPosition
        let nodePosition = node.worldPosition
        
        // 2. Calculate the relative vector
        let relativeVector = SCNVector3(
            nodePosition.x - cameraPosition.x,
            nodePosition.y - cameraPosition.y,
            nodePosition.z - cameraPosition.z
        ).normalized()
        
        // 3. Get the camera's forward direction (negative Z-axis in camera's space)
        let cameraForward = SCNVector3(-camera.worldTransform.m31,
                                       -camera.worldTransform.m32,
                                       -camera.worldTransform.m33).normalized()
        
        // 4. Define axis vectors
        let xAxis = SCNVector3(1, 0, 0) // X-axis
        let yAxis = SCNVector3(0, 1, 0) // Y-axis
        let zAxis = SCNVector3(0, 0, 1) // Z-axis
        
        // 5. Calculate angles using the dot product
        let angleX = acos(relativeVector.dotProduct(with: xAxis)) * relativeVector.signRelativeTo(axis: xAxis)
        let angleY = acos(relativeVector.dotProduct(with: yAxis)) * relativeVector.signRelativeTo(axis: yAxis)
        let angleZ = acos(relativeVector.dotProduct(with: zAxis)) * relativeVector.signRelativeTo(axis: zAxis)
        
        return (x: angleX, y: angleY, z: angleZ)
    }

}

extension SCNVector3 {
    // Dot product
    func dotProduct(with vector: SCNVector3) -> Float {
        return x * vector.x + y * vector.y + z * vector.z
    }
    
    // Cross product
    func crossProduct(with vector: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            y * vector.z - z * vector.y,
            z * vector.x - x * vector.z,
            x * vector.y - y * vector.x
        )
    }
    
    // Magnitude (length) of the vector
    var magnitude: Float {
        return sqrt(x * x + y * y + z * z)
    }
    
    // Normalize the vector
    func normalized() -> SCNVector3 {
        let length = magnitude
        return length == 0 ? self : SCNVector3(x / length, y / length, z / length)
    }
    func signRelativeTo(axis: SCNVector3) -> Float {
        let cross = self.crossProduct(with: axis)
        return cross.magnitude == 0 ? 1 : (cross.x + cross.y + cross.z >= 0 ? 1 : -1)
    }
}
