//
//  MetalView.swift
//  RndMetal
//
//  Created by Vishwas Prakash on 17/12/24.
//

import Metal
import MetalKit
import UIKit

struct VertexInfo{
    var position: SIMD3<Float>
    var textureCoordinate: SIMD2<Float>
}

struct LayerInfo{
    let name: String
    let layerPriority: Int
    let image: UIImage?
    var texture: MTLTexture?
}

class MetalSineWaveView: UIView {
    // Metal rendering properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer
    private var animationBuffer: MTLBuffer
    private var sourceTexture: MTLTexture?
    private var vertexInfo: [VertexInfo] = []
    
    // Animation properties
    private var displayLink: CADisplayLink?
    private var time: Float = 0.0
    
    // Image to render
    private let imageSet: [String: UIImage]
    private var layerInfo: [LayerInfo] = []
    
    // Metalayer for rendering
    private var metalLayer: CAMetalLayer!
    
    init?(frame: CGRect, imageSet:  [String: UIImage]) {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Cannot create Metal device")
            return nil
        }
        
        self.device = device
        self.imageSet = imageSet
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("Cannot create command queue")
            return nil
        }
        self.commandQueue = commandQueue
        
        // x, y, u, v
        vertexInfo = [
            VertexInfo(position: SIMD3(-1.0, -1.0, 0.0), textureCoordinate: SIMD2(0.0, 1.0)),
            VertexInfo(position: SIMD3(1.0, -1.0, 0.0), textureCoordinate: SIMD2(1.0, 1.0)),
            VertexInfo(position: SIMD3(-1.0, 1.0, 0.0), textureCoordinate: SIMD2(0.0, 0.0)),
            VertexInfo(position: SIMD3(1.0, 1.0, 0.0), textureCoordinate: SIMD2(1.0, 0.0))
        ]
        
        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(
            bytes: vertexInfo,
            length: MemoryLayout<VertexInfo>.stride * vertexInfo.count,
            options: []
        ) else {
            print("Cannot create vertex buffer")
            return nil
        }
        
        self.vertexBuffer = vertexBuffer
        
        // Create animation time buffer
        guard let animationBuffer = device.makeBuffer(length: MemoryLayout<Float>.size, options: []) else {
            print("Cannot create animation buffer")
            return nil
        }
        
        self.animationBuffer = animationBuffer

        // Call super after all initializations
        super.init(frame: frame)
        self.backgroundColor = .cyan
        assignLayer(imageSet: imageSet)
        createRenderPipeline()
        // Setup Metal layer
        setupMetalLayer()
        
        // Load image texture
        loadTextures()
        // Setup animation
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupMetalLayer() {
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.frame = bounds
        metalLayer.isOpaque = false
        layer.addSublayer(metalLayer)
    }
    
    private func assignLayer(imageSet: [String:UIImage]){
        for imageName in imageSet.keys{
            let layerPriority = extractIntValue(from: imageName) ?? 0
            let layer = LayerInfo(name: imageName, layerPriority: layerPriority, image: imageSet[imageName])
            layerInfo.append(layer)
        }
    }
    
    private func loadTextures() {
        let textureLoader = MTKTextureLoader(device: device)

        for var layer in layerInfo{
            if let image = layer.image, let cgImage = image.cgImage{
                do {
                    layer.texture = try textureLoader.newTexture(
                        cgImage: cgImage,
                        options: [:]
                    )
                    sourceTexture = layer.texture
                } catch {
                    print("Error loading texture: \(error)")
                }
            }
        }
    }
    
    
    private func createRenderPipeline() -> MTLRenderPipelineState? {
        // Create shader functions
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShaderWithSineWave"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            print("Cannot create shader functions")
            return nil
        }
        
        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexInfo>.stride
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // Create render pipeline state
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Error creating render pipeline state: \(error)")
            return nil
        }
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(step))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func step(displayLink: CADisplayLink) {
        // Update time for animation
        time += Float(displayLink.duration)
        
        // Update time buffer
        let timePtr = animationBuffer.contents().bindMemory(to: Float.self, capacity: 1)
        timePtr.pointee = time
        
        // Trigger rendering
        render()
    }
    
    private func render() {
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              
              let sourceTexture = sourceTexture else {
            return
        }
        let renderPassDescriptor = createRenderPassDescriptor(drawable: drawable)
              
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Set render pipeline state
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set time buffer
        renderEncoder.setVertexBuffer(animationBuffer, offset: 0, index: 1)
        
        // Set texture
        renderEncoder.setFragmentTexture(sourceTexture, index: 0)
        
        // Draw
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        // End encoding
        renderEncoder.endEncoding()
        
        // Commit and present
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func createRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        return renderPassDescriptor
    }
}

func extractIntValue(from string: String) -> Int? {
    // Split the string by the "_" character
    let components = string.split(separator: "_")
    
    // Take the first component and try to convert it to an Int
    return Int(components.first ?? "")
}
