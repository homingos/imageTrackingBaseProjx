//
//  ARMetalViewDebug.swift
//  maskImage
//
//  Created by Vishwas Prakash on 18/12/24.
//

import Foundation
import MetalKit

struct VertexDebug {
    var position: SIMD3<Float>
    var texCoord: SIMD2<Float>
    var textureIndex: UInt32
}

class LayerImage {
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


class ARMetalViewDebug: MTKView {
    private var commandQueue: MTLCommandQueue!
    private var renderPipelineState: MTLRenderPipelineState!
    private var vertexBuffers: [MTLBuffer] = []
    private var indexBuffers: [MTLBuffer] = []
    private var uniformBuffer: MTLBuffer!
    private var samplerState: MTLSamplerState?
    
    private var anchorTransform: simd_float4x4?
    private var cameraTransform: simd_float4x4?
    private var projectionMatrix: simd_float4x4?
    
    private var imageDic: [String: UIImage]!
    private var layerImages: [LayerImage] = []
    
    private var stencilState: MTLDepthStencilState?
    private var maskRenderPipelineState: MTLRenderPipelineState!
    
    private var writeStencilState: MTLDepthStencilState?
    private var testStencilState: MTLDepthStencilState?
    
    init?(frame: CGRect, device: MTLDevice, imageDic: [String: UIImage]) {
        super.init(frame: frame, device: device)
        self.device = device
        
        // Configure view properties
        self.colorPixelFormat = .bgra8Unorm
        self.depthStencilPixelFormat = .depth32Float_stencil8
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.framebufferOnly = false
        self.enableSetNeedsDisplay = true
        
        self.imageDic = imageDic
        
        setupMetal()
        
        setLayerImage(layerImage: imageDic)
        
        //        setupDefaultVertices()
    }
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setLayerImage(layerImage: [String: UIImage]){
        guard let device else { return }
        
        self.imageDic = layerImage
        let textureLoader = MTKTextureLoader(device: device)
        let textureOptions: [MTKTextureLoader.Option: Any] = [
            .generateMipmaps: true,                     // Enable mipmapping
            .SRGB: false,                               // Linear color space for correct rendering
            .textureUsage: MTLTextureUsage([.shaderRead, .renderTarget]).rawValue,
            .allocateMipmaps: true                      // Allocate space for mipmaps
        ]
        
        for ele in imageDic{
            let imageName = ele.key
            
            let layerPriority = extractIntValue(from: imageName) ?? 0
            let layer = LayerImage(name: imageName, layerPriority: layerPriority, image: ele.value)
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
            layerImages.append(layer)
        }
        
        layerImages.sort { $0.layerPriority < $1.layerPriority }
        setupLayerVertices()
        
    }
    
    private func setupMetal() {
        guard let device = self.device else {
            print("No Metal device")
            return
        }
        
        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            print("Failed to create command queue")
            return
        }
        commandQueue = queue
        print("Command queue created")
        
        createRenderPipeline()
        createMaskRenderPipeline()
        createStencilState()
        createSamplerState()
    }
    
    private func createSamplerState() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device?.makeSamplerState(descriptor: descriptor)
    }
    
    private func createStencilState() {
        // Write stencil state (for mask)
        let writeDescriptor = MTLDepthStencilDescriptor()
        writeDescriptor.depthCompareFunction = .always
        writeDescriptor.isDepthWriteEnabled = false
        
        let writeFaceStencil = MTLStencilDescriptor()
        writeFaceStencil.stencilCompareFunction = .always
        writeFaceStencil.stencilFailureOperation = .zero
        writeFaceStencil.depthFailureOperation = .zero
        writeFaceStencil.depthStencilPassOperation = .replace
        writeFaceStencil.readMask = 0xFF
        writeFaceStencil.writeMask = 0xFF
        writeDescriptor.frontFaceStencil = writeFaceStencil
        writeDescriptor.backFaceStencil = writeFaceStencil
        
        writeStencilState = device?.makeDepthStencilState(descriptor: writeDescriptor)
        
        // Test stencil state (for content)
        let testDescriptor = MTLDepthStencilDescriptor()
        testDescriptor.depthCompareFunction = .always
        testDescriptor.isDepthWriteEnabled = false
        
        let testFaceStencil = MTLStencilDescriptor()
        testFaceStencil.stencilCompareFunction = .equal
        testFaceStencil.stencilFailureOperation = .zero
        testFaceStencil.depthFailureOperation = .zero
        testFaceStencil.depthStencilPassOperation = .keep
        testFaceStencil.readMask = 0xFF
        testFaceStencil.writeMask = 0xFF
        testDescriptor.frontFaceStencil = testFaceStencil
        testDescriptor.backFaceStencil = testFaceStencil
        
        testStencilState = device?.makeDepthStencilState(descriptor: testDescriptor)
    }
    
    private func createMaskRenderPipeline() {
        guard let device = self.device else { return }
        
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "maskVertexShader"),
              let fragmentFunction = library.makeFunction(name: "maskFragmentShader") else {
            print("Failed to create mask shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Mask Render Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        // Configure color attachment for mask pass
        let colorAttachment = pipelineDescriptor.colorAttachments[0]
        colorAttachment?.pixelFormat = self.colorPixelFormat
        colorAttachment?.isBlendingEnabled = false
        colorAttachment?.writeMask = [] // Don't write to color buffer
        
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        // Add vertex descriptor for mask pipeline
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .uint
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexDebug>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            maskRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create mask pipeline state: \(error)")
        }
    }
    
    
    private func createRenderPipeline() {
        guard let device = self.device else { return }
        
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShaderDebug"),
              let fragmentFunction = library.makeFunction(name: "fragmentShaderDebug") else {
            print("Failed to create shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Debug Render Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        // Configure blending
        let attachment = pipelineDescriptor.colorAttachments[0]
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Configure vertex descriptor with texture index
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .uint
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<VertexDebug>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupLayerVertices() {
        vertexBuffers.removeAll()
        indexBuffers.removeAll()
        
        for (index, layer) in layerImages.enumerated() {
            // Calculate offset based on layer priority
            let zOffset =  Float(layer.layerPriority) * 0.1 // Small z-offset to prevent z-fighting
            print("z offset: \(zOffset)")
            let vertices: [VertexDebug] = [
                VertexDebug(position: SIMD3<Float>(-0.5, zOffset, -0.5 ), texCoord: SIMD2<Float>(0.0, 1.0), textureIndex: UInt32(index)),
                VertexDebug(position: SIMD3<Float>(0.5, zOffset, -0.5), texCoord: SIMD2<Float>(1.0, 1.0), textureIndex: UInt32(index)),
                VertexDebug(position: SIMD3<Float>(-0.5, zOffset, 0.5), texCoord: SIMD2<Float>(0.0, 0.0), textureIndex: UInt32(index)),
                VertexDebug(position: SIMD3<Float>(0.5, zOffset, 0.5), texCoord: SIMD2<Float>(1.0, 0.0), textureIndex: UInt32(index))
            ]
            
            let indices: [UInt16] = [
                0, 1, 2,  // First triangle
                2, 1, 3   // Second triangle
            ]
            
            if let vertexBuffer = device?.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<VertexDebug>.stride,
                options: .storageModeShared
            ) {
                vertexBuffers.append(vertexBuffer)
            }
            
            if let indexBuffer = device?.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt16>.stride,
                options: .storageModeShared
            ) {
                indexBuffers.append(indexBuffer)
            }
        }
        
        let uniformBufferSize = MemoryLayout<simd_float4x4>.stride * 3
        uniformBuffer = device?.makeBuffer(length: uniformBufferSize, options: .storageModeShared)
    }
    
    private func loadTexture(named name: String) -> MTLTexture? {
        guard let device = device else {
            print("Failed to create texture loader")
            return nil
        }
        
        let textureLoader = MTKTextureLoader(device: device)
        guard let image = UIImage(named: name)?.cgImage else {
            print("Failed to load image: \(name)")
            return nil
        }
        
        do {
            let textureOptions: [MTKTextureLoader.Option: Any] = [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue,
                .generateMipmaps: true
            ]
            
            let texture = try textureLoader.newTexture(cgImage: image, options: textureOptions)
            print("Texture loaded successfully")
            return texture
        } catch {
            print("Failed to create texture: \(error)")
            return nil
        }
    }
    
    // Function to update transforms
    func updateTransforms(
        anchorTransform: simd_float4x4,
        cameraTransform: simd_float4x4?,
        projectionMatrix: simd_float4x4
    ) {
        self.anchorTransform = anchorTransform
        self.cameraTransform = cameraTransform
        self.projectionMatrix = projectionMatrix
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let uniformBuffer = uniformBuffer,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let writeStencilState = writeStencilState,
              let testStencilState = testStencilState else {
            return
        }
        
        // First pass - render mask to stencil buffer
        renderPassDescriptor.stencilAttachment.clearStencil = 0
        renderPassDescriptor.stencilAttachment.loadAction = .clear
        renderPassDescriptor.stencilAttachment.storeAction = .store
        
        // Clear color for first pass
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let maskEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        maskEncoder.setRenderPipelineState(maskRenderPipelineState)
        maskEncoder.setDepthStencilState(writeStencilState)
        maskEncoder.setStencilReferenceValue(1)
        
        // Render mask geometry
        let maskVertices = createMaskVertices()
        let maskVertexBuffer = device?.makeBuffer(
            bytes: maskVertices,
            length: maskVertices.count * MemoryLayout<VertexDebug>.stride,
            options: .storageModeShared
        )
        
        maskEncoder.setVertexBuffer(maskVertexBuffer, offset: 0, index: 0)
        maskEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        maskEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        maskEncoder.endEncoding()
        
        // Second pass - ensure we're keeping the stencil
        renderPassDescriptor.stencilAttachment.loadAction = .load
        renderPassDescriptor.colorAttachments[0].loadAction = .load
        
        // Second pass - render content with stencil test
        let contentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        contentEncoder.setRenderPipelineState(renderPipelineState)
        contentEncoder.setDepthStencilState(testStencilState)
        contentEncoder.setStencilReferenceValue(1)  // Must match the value written in the mask pass
        contentEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Update and set uniforms
        updateUniforms(uniformBuffer)
        contentEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Draw each layer
        for i in 0..<layerImages.count {
            if let texture = layerImages[i].texture {
                contentEncoder.setVertexBuffer(vertexBuffers[i], offset: 0, index: 0)
                contentEncoder.setFragmentTexture(texture, index: i)
                
                contentEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: 6,
                    indexType: .uint16,
                    indexBuffer: indexBuffers[i],
                    indexBufferOffset: 0
                )
            }
        }
        
        contentEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func createMaskVertices() -> [VertexDebug] {
        let size: Float = 0.5 // Adjust this value to change the size of the mask
        return [
            VertexDebug(position: SIMD3<Float>(-size, 0, -size), texCoord: SIMD2<Float>(0, 1), textureIndex: 0),
            VertexDebug(position: SIMD3<Float>(size,0, -size), texCoord: SIMD2<Float>(1, 1), textureIndex: 0),
            VertexDebug(position: SIMD3<Float>(-size, 0, size), texCoord: SIMD2<Float>(0, 0), textureIndex: 0),
            VertexDebug(position: SIMD3<Float>(size, 0, size), texCoord: SIMD2<Float>(1, 0), textureIndex: 0)
        ]
    }
    
    private func updateUniforms(_ buffer: MTLBuffer) {
        let matrices = buffer.contents().assumingMemoryBound(to: simd_float4x4.self)
        if let anchor = anchorTransform,
           let camera = cameraTransform,
           let projection = projectionMatrix {
            matrices[0] = anchor
            matrices[1] = camera
            matrices[2] = projection
        } else {
            matrices[0] = matrix_identity_float4x4
            matrices[1] = matrix_identity_float4x4
            matrices[2] = matrix_identity_float4x4
        }
    }
}

func extractIntValue(from string: String) -> Int? {
    // Split the string by the "_" character
    let components = string.split(separator: "_")
    
    // Take the first component and try to convert it to an Int
    return Int(components.first ?? "")
}
