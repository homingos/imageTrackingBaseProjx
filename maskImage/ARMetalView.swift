//
//  ARMetalView.swift
//  maskImage
//
//  Created by Vishwas Prakash on 18/12/24.
//

import Metal
import MetalKit
import ARKit

class Vertex {
    var position: SIMD3<Float>
    
    init(position: SIMD3<Float>) {
        self.position = position
    }
}

class ARMetalView: MTKView {
    // Metal objects
    private var commandQueue: MTLCommandQueue!
    private var renderPipelineState: MTLRenderPipelineState!
    private var anchorTransform: simd_float4x4?
    private var cameraTransform: simd_float4x4?
    private var isTracking: Bool = false
    private var lastValidTransform: simd_float4x4?
    
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    
    // Vertex data
    private var vertices: [Float] = []
    
    // Tracked image info
    private var imageTransform: simd_float4x4 = matrix_identity_float4x4
    private var imageSize: CGSize = .zero
    
    // Camera info
    private var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    private var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    
    init?(frame: CGRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        self.device = device
        
        // Configure view properties for transparency
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        self.depthStencilPixelFormat = .depth32Float
        self.framebufferOnly = false
        self.autoResizeDrawable = true
        self.preferredFramesPerSecond = 60
        self.isOpaque = false
        
        setupMetal()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateTransforms(anchorTransform: simd_float4x4?, cameraTransform: simd_float4x4?) {
        if let anchorTransform = anchorTransform {
            isTracking = true
            lastValidTransform = anchorTransform
        }
        
        self.anchorTransform = anchorTransform ?? lastValidTransform
        self.cameraTransform = cameraTransform
        
        // Request redraw
        setNeedsDisplay()
    }
    private func setupMetal() {
        // Create command queue
        guard let queue = device?.makeCommandQueue() else {
            print("Failed to create command queue")
            return
        }
        commandQueue = queue
        
        // Create render pipeline
        createRenderPipeline()
        
        // Initialize default vertices for a plane
        setupDefaultVertices()
        
        print("Metal setup completed")
    }
    
    func hideContent() {
        isTracking = false
        anchorTransform = nil
        setNeedsDisplay()
    }
    
    private func createRenderPipeline() {
        guard let device = self.device else {
            print("No Metal device")
            return
        }
        
        let library = device.makeDefaultLibrary()
        print("Default library: \(String(describing: library))")
        
        guard let vertexFunction = library?.makeFunction(name: "vertexShader"),
              let fragmentFunction = library?.makeFunction(name: "fragmentShader") else {
            print("Failed to create shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        
        // Set up vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        // Set the stride
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        // Enable blending
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("Pipeline state created successfully")
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupDefaultVertices() {
        let vertices: [Vertex] = [
            Vertex(position: SIMD3<Float>(-1.0, -1.0, 0.0)),  // Bottom left
            Vertex(position: SIMD3<Float>(1.0, -1.0, 0.0)),   // Bottom right
            Vertex(position: SIMD3<Float>(-1.0, 1.0, 0.0)),   // Top left
            Vertex(position: SIMD3<Float>(1.0, 1.0, 0.0))     // Top right
        ]
        
        // Create indices for triangle strip
        let indices: [UInt16] = [
            0, 1, 2, 3  // Triangle strip order
        ]
        
        // Create vertex buffer
        vertexBuffer = device?.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Vertex>.stride,
            options: .storageModeShared
        )
        
        // Create index buffer
        indexBuffer = device?.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt16>.stride,
            options: .storageModeShared
        )
    }
    
    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Set up matrices
        let modelMatrix = anchorTransform ?? lastValidTransform ?? matrix_identity_float4x4
        let viewMatrix = cameraTransform ?? matrix_identity_float4x4
        
        let aspect = Float(drawableSize.width / drawableSize.height)
        let fov = Float(70.0 * .pi / 180.0)
        let projectionMatrix = simd_float4x4(perspectiveProjectionFov: fov,
                                             aspectRatio: aspect,
                                             nearZ: 0.1,
                                             farZ: 100.0)
        
        var matrices = [modelMatrix, viewMatrix, projectionMatrix]
        renderEncoder.setVertexBytes(&matrices,
                                     length: MemoryLayout<simd_float4x4>.stride * 3,
                                     index: 1)
        
        // Draw using indexed rendering
        renderEncoder.drawIndexedPrimitives(type: .triangleStrip,
                                            indexCount: 4,
                                            indexType: .uint16,
                                            indexBuffer: indexBuffer,
                                            indexBufferOffset: 0)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension simd_float4x4 {
    init(perspectiveProjectionFov fovRadians: Float,
         aspectRatio aspect: Float,
         nearZ: Float,
         farZ: Float) {
        let ys = 1 / tanf(fovRadians * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        
        self.init(columns: (
            simd_float4(xs, 0, 0, 0),
            simd_float4(0, ys, 0, 0),
            simd_float4(0, 0, zs, -1),
            simd_float4(0, 0, zs * nearZ, 0)
        ))
    }
    
    init(orthographicProjectionWithLeft left: Float,
         right: Float,
         bottom: Float,
         top: Float,
         nearZ: Float,
         farZ: Float) {
        let xs = 2 / (right - left)
        let ys = 2 / (top - bottom)
        let zs = 1 / (nearZ - farZ)
        
        let tx = (left + right) / (left - right)
        let ty = (top + bottom) / (bottom - top)
        let tz = nearZ / (nearZ - farZ)
        
        self.init(columns: (
            simd_float4(xs, 0, 0, 0),
            simd_float4(0, ys, 0, 0),
            simd_float4(0, 0, zs, 0),
            simd_float4(tx, ty, tz, 1)
        ))
    }
}
