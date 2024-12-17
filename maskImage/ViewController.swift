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
    
    
    private var maskNode: SCNNode?
    
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

        let configuration = ARImageTrackingConfiguration()
        configuration.trackingImages = referenceImages
        configuration.maximumNumberOfTrackedImages = 1

        sceneView.session.run(configuration)
        
    }
    
        
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }

        let referenceImage = imageAnchor.referenceImage
        let width = referenceImage.physicalSize.width
        let height = referenceImage.physicalSize.height

        // Create the main wider plane
        let plane = SCNPlane(width: width * 1.5, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = UIImage(named: "background.jpg")
        material.isDoubleSided = true
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.geometry?.materials = [material]
        planeNode.eulerAngles.x = -.pi / 2
        
        let node = SCNNode()
        node.addChildNode(planeNode)
        
        return node
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
}
