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

class LayerInfo {
    let name: String
    let layerPriority: Int
    let image: UIImage?
    var texture: MTLTexture?

    // Initializer
    init(name: String, layerPriority: Int, image: UIImage?, texture: MTLTexture? = nil) {
        self.name = name
        self.layerPriority = layerPriority
        self.image = image
        self.texture = texture
    }
}

class MetalSineWaveView: UIView {
    // Metal rendering properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffers: [MTLBuffer] = []  // One buffer per layer
    private var layerTextures: [MTLTexture] = []
    private var animationBuffer: MTLBuffer
    private var vertexInfo: [VertexInfo] = []
    
    // Animation properties
    private var displayLink: CADisplayLink?
    private var time: Float = 0.0
    var value: Float = 0.0
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
        
        // Create animation time buffer
        guard let animationBuffer = device.makeBuffer(length: MemoryLayout<Float>.size, options: []) else {
            print("Cannot create animation buffer")
            return nil
        }
        
        self.animationBuffer = animationBuffer

        // Call super after all initializations
        super.init(frame: frame)
        self.backgroundColor = .black
        assignLayer(imageSet: imageSet)
        setupVertexBuffers()
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
    
    private func setupVertexBuffers() {
        let sortedLayers = layerInfo.sorted { $0.layerPriority < $1.layerPriority }
        
        for (index, layer) in sortedLayers.enumerated() {

            // Create vertices for each layer with appropriate z-value
            let zValue = Float(index) * 0.1 // Adjust z-spacing as needed
            let vertices = [
                VertexInfo(position: SIMD3(-1.0, -1.0, zValue), textureCoordinate: SIMD2(0.0, 1.0)),
                VertexInfo(position: SIMD3(1.0, -1.0, zValue), textureCoordinate: SIMD2(1.0, 1.0)),
                VertexInfo(position: SIMD3(-1.0, 1.0, zValue), textureCoordinate: SIMD2(0.0, 0.0)),
                VertexInfo(position: SIMD3(1.0, 1.0, zValue), textureCoordinate: SIMD2(1.0, 0.0))
            ]
            print("layer: \(zValue)")
            guard let buffer = device.makeBuffer(
                bytes: vertices,
                length: MemoryLayout<VertexInfo>.stride * vertices.count,
                options: []
            ) else { continue }
            
            vertexBuffers.append(buffer)
        }
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
        let textureOptions: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: true,                     // Enable mipmapping
            .SRGB: false,                               // Linear color space for correct rendering
            .textureUsage: MTLTextureUsage([.shaderRead, .renderTarget]).rawValue,
            .allocateMipmaps: true                      // Allocate space for mipmaps
        ]
        for layer in layerInfo {
            if let image = layer.image, let cgImage = image.cgImage {
                do {
                    // Create texture descriptor for high quality
                    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: cgImage.width,
                        height: cgImage.height,
                        mipmapped: true
                    )
                    textureDescriptor.usage = [.shaderRead, .renderTarget]
                    textureDescriptor.storageMode = .private
                    textureDescriptor.sampleCount = 1
                    
                    layer.texture = try textureLoader.newTexture(
                        cgImage: cgImage,
                        options: textureOptions
                    )
                    print("Layer texture loaded with high quality settings")
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
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        if let attachment = pipelineDescriptor.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .sourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        } else {
            print("Depth is not initlized")
        }
        
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
        timePtr.pointee = value
        
        // Trigger rendering
        render()
    }
    
    private func render() {
        guard let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        let renderPassDescriptor = createRenderPassDescriptor(drawable: drawable)
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(bounds.width),
            height: Int(bounds.height),
            mipmapped: false)
        depthDescriptor.usage = .renderTarget
        guard let depthTexture = device.makeTexture(descriptor: depthDescriptor) else { return }
        
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Set render pipeline state
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set time buffer
        renderEncoder.setVertexBuffer(animationBuffer, offset: 0, index: 1)
        
        let sortedLayers = layerInfo.sorted { $0.layerPriority > $1.layerPriority }
        for (index, layer) in sortedLayers.enumerated() {
            guard let texture = layer.texture else {
                print("text is nil")
                continue
            }
            
            renderEncoder.setVertexBuffer(vertexBuffers[index], offset: 0, index: 0)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
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
