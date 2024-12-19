//
//  ViewController.swift
//  maskImage
//
//  Created by Apple  on 05/12/24.
//

import UIKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    @IBOutlet weak var sceneView: ARSCNView!
    private var metalView: ARMetalViewDebug?
    private var arSession: ARSession!
    private var currentImageAnchor: ARImageAnchor?
    
    
    override func viewDidLoad() {
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
        
        // Create Metal view
        metalView = ARMetalViewDebug(frame: view.bounds, device: device)
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
            }
        } else {
            print("Reference images not found")
        }
        
        // Run the session with debug options
        let options: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        arSession.run(configuration, options: options)
        
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
        // Get camera transform
        let camera = frame.camera
        let cameraTransform = camera.transform
        // If we have a current image anchor, update transforms
        if let currentAnchor = currentImageAnchor {
            //            metalView?.updateTransforms(anchorTransform: currentAnchor.transform, cameraTransform: cameraTransform)
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
                metalView?.updateTransforms(anchorTransform: modelMatrix, cameraTransform: frame.camera.viewMatrix(for: .portrait), projectionMatrix: projectionMatrix)
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
                metalView?.updateTransforms(anchorTransform: modelMatrix, cameraTransform: frame.camera.viewMatrix(for: .portrait), projectionMatrix: projectionMatrix)
            }
        }
    }
}
