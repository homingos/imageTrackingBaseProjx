//
//  ViewController.swift
//  maskImage
//
//  Created by Apple  on 05/12/24.
//

import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, SCNSceneRendererDelegate, ARMetalViewDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    private var metalView: ARMetalView?
    private var arSession: ARSession!
    private var currentImageAnchor: ARImageAnchor?
    private var displayLink: CADisplayLink?
    private var viewportSize: CGSize!
    
    override func viewDidLoad() {
        viewportSize = view.bounds.size

        super.viewDidLoad()
        
        // Set up AR Scene View
        
        sceneView.delegate = self
        
        // Create and set up AR Session
        arSession = ARSession()
        arSession.delegate = self  // Set the session delegate
        sceneView.session = arSession
        sceneView.scene = SCNScene()
        
        print("Setting up AR Session and delegates")
        
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }
        
        let rootImages = [
            "0", "-1", "-2", "-2_1", "-3", "-4"
        ]
        var imageSet: [String: LayerImage] = [:]
        
        for imageName in rootImages {
            if let image = UIImage(named: imageName) {
                let layerPriority = extractIntValue(from: imageName) ?? 0
                let offset = SIMD3(0.0, Float(layerPriority), 0.0)
                var scale: Float = 1.0
                if imageName == "-4" {
                    scale = 2.0
                }
                imageSet[imageName] = LayerImage(name: imageName, offset: offset, image: image, scale: scale)
            } else {
                print("Missing image: \(imageName)")
            }
        }
        // Create Metal view
        metalView = ARMetalView(frame: view.bounds, device: device, layerDic: imageSet, viewControllerDelegate: self)
        if let metalView = metalView {
            view.addSubview(metalView)
            metalView.frame = view.bounds
            metalView.backgroundColor = .clear
            metalView.isOpaque = false
            
            metalView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                metalView.topAnchor.constraint(equalTo: view.topAnchor),
                metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            
            // Force initial render
            metalView.setNeedsDisplay()
        }
        
        view.bringSubviewToFront(metalView!)
        
        // Configure AR
        let configuration = ARImageTrackingConfiguration()
        if let trackedImages = ARReferenceImage.referenceImages(inGroupNamed: "ImageForAR", bundle: nil) {
            configuration.trackingImages = trackedImages
            print("Reference images found: \(trackedImages.count)")
            configuration.maximumNumberOfTrackedImages = 1
            
            // Print details about the reference images
            for image in trackedImages {
                print("Reference image name: \(image.name ?? "unnamed")")
                print("Physical size: \(image.physicalSize)")
                metalView?.setTargetSize(targetSize: image.physicalSize)
            }
        } else {
            print("Reference images not found")
        }
        
        // Run the session with debug options
        let options: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        arSession.run(configuration, options: options)
        
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func displayLinkDidFire() {
        guard let frame = sceneView.session.currentFrame else { return }
        
        let camera = frame.camera
        let projectionMatrix = camera.projectionMatrix(for: .portrait, viewportSize: view.bounds.size, zNear: 0.001, zFar: 1000)
        
        if let imageAnchor = currentImageAnchor, imageAnchor.isTracked {
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(imageAnchor.transform, coordinateSpaceTransform)
            
            metalView?.updateTransforms(
                anchorTransform: modelMatrix,
                cameraTransform: camera.viewMatrix(for: .portrait),
                projectionMatrix: projectionMatrix
            )
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Invalidate display link when view disappears
        displayLink?.invalidate()
        displayLink = nil
    }
    override func viewDidAppear(_ animated: Bool) {
        DispatchQueue.main.async{
            guard let metalView = self.metalView else { return }
            self.view.bringSubviewToFront(metalView)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView?.setNeedsDisplay()
    }
    
}

extension ViewController {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Get camera transform and projection matrix for this frame
        let camera = frame.camera
        let projectionMatrix = camera.projectionMatrix(for: .portrait,
                                                       viewportSize: view.bounds.size,
                                                       zNear: 0.001,
                                                       zFar: 1000)
        
        // If we have a current image anchor
        if let imageAnchor = currentImageAnchor {
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(imageAnchor.transform, coordinateSpaceTransform)
            
//             Update transforms every frame with latest camera view matrix
                        metalView?.updateTransforms(
                            anchorTransform: modelMatrix,
                            cameraTransform: camera.viewMatrix(for: .portrait),
                            projectionMatrix: projectionMatrix
                        )
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            print("Image anchor added: \(imageAnchor.referenceImage.name ?? "unnamed")")
            currentImageAnchor = imageAnchor
            
            if let frame = session.currentFrame {
                print("calling update: \(imageAnchor.transform) + \(frame.camera.transform)")
                let projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: view.bounds.size, zNear: 0.001, zFar: 1000)
                var coordinateSpaceTransform = matrix_identity_float4x4
                coordinateSpaceTransform.columns.2.z = -1.0
                
                let modelMatrix = simd_mul(imageAnchor.transform, coordinateSpaceTransform)
//                metalView?.updateTransforms(anchorTransform: modelMatrix, cameraTransform: frame.camera.viewMatrix(for: .portrait), projectionMatrix: projectionMatrix)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            
            currentImageAnchor = imageAnchor
            if imageAnchor.isTracked, let frame = session.currentFrame {
                let projectionMatrix = frame.camera.projectionMatrix(for: .portrait, viewportSize: view.bounds.size, zNear: 0.001, zFar: 1000)
                var coordinateSpaceTransform = matrix_identity_float4x4
                coordinateSpaceTransform.columns.2.z = -1.0
                
                let modelMatrix = simd_mul(imageAnchor.transform, coordinateSpaceTransform)
                //                metalView?.updateTransforms(anchorTransform: modelMatrix, cameraTransform: frame.camera.viewMatrix(for: .portrait), projectionMatrix: projectionMatrix)
                //                print("did update")
            }
        }
    }
    
    func willUpdateDraw(layerImages: [LayerImage]) -> [SIMD3<Float>]? {
        
        return nil
        // if want to animate
        var offsets: [SIMD3<Float>] = []
        for ele in layerImages {
            var offset = ele.offset
            offset.y = 0.0
            offset.x = 0.01
            offsets.append(offset)
        }
        return offsets
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        
        // Get camera transform and projection matrix for this frame
        let camera = frame.camera
        let projectionMatrix = camera.projectionMatrix(for: .portrait,
                                                       viewportSize: viewportSize,
                                                       zNear: 0.001,
                                                       zFar: 1000)
        
        // If we have a current image anchor
        if let imageAnchor = currentImageAnchor {
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(imageAnchor.transform, coordinateSpaceTransform)
            
//             Update transforms every frame with latest camera view matrix
            DispatchQueue.main.async {
                self.metalView?.updateTransforms(
                    anchorTransform: modelMatrix,
                    cameraTransform: camera.viewMatrix(for: .portrait),
                    projectionMatrix: projectionMatrix
                )
            }
        }
    }
}
