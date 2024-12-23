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
    
    init?(frame: CGRect, device: MTLDevice, imageDic: [String: UIImage]) {
        super.init(frame: frame, device: device)
        self.device = device
        
        // Configure view properties
        self.colorPixelFormat = .bgra8Unorm
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
    
    //    private func setupDefaultVertices() {
    //        // Define vertices in ARKit's coordinate system
    //        // The image anchor's transform expects the plane to be in the X-Y plane
    //        let rectangleNum = UInt16(layerImages.count)
    //
    //        for i in 0..<rectangleNum {
    //            let zLayer = Float(layerImages[Int(i)].layerPriority) * 0.5
    //
    //            vertices.append(VertexDebug(position: SIMD3<Float>(-0.5,zLayer , -0.5), texCoord: SIMD2<Float>(0.0, 1.0))) // Bottom left
    //            vertices.append(VertexDebug(position: SIMD3<Float>(0.5, zLayer, -0.5), texCoord: SIMD2<Float>(1.0, 1.0)))  // Bottom right
    //            vertices.append(VertexDebug(position: SIMD3<Float>(-0.5,zLayer, 0.5), texCoord: SIMD2<Float>(0.0, 0.0)))  // Top left
    //            vertices.append(VertexDebug(position: SIMD3<Float>(0.5, zLayer, 0.5), texCoord: SIMD2<Float>(1.0, 0.0)))    // Top right
    //
    //            // Use counter-clockwise winding for front-facing triangles
    //            let startIndex = i
    //            indices.append(contentsOf: [
    //                startIndex, startIndex + 1, startIndex + 2, // First triangle
    //                startIndex + 2, startIndex + 1, startIndex + 3 // Second triangle
    //            ])
    //        }
    //
    //        vertexBuffer = device?.makeBuffer(
    //            bytes: vertices,
    //            length: vertices.count * MemoryLayout<VertexDebug>.stride,
    //            options: .storageModeShared
    //        )
    //
    //        indexBuffer = device?.makeBuffer(
    //            bytes: indices,
    //            length: indices.count * MemoryLayout<UInt16>.stride,
    //            options: .storageModeShared
    //        )
    //
    //        // Create uniform buffer for matrices
    //
    //    }
    
    override func draw(_ rect: CGRect) {
        guard let uniformBuffer else { return }

        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let renderPassDescriptor = currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // Update uniform buffer with matrices
        let matrices = uniformBuffer.contents().assumingMemoryBound(to: simd_float4x4.self)
        if let anchor = anchorTransform,
           let camera = cameraTransform,
           let projection = projectionMatrix {
            matrices[0] = anchor
            matrices[1] = camera
            matrices[2] = projection
        } else {
            let identity = matrix_identity_float4x4
            matrices[0] = identity
            matrices[1] = identity
            matrices[2] = identity
        }
        
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Draw each layer
        for i in 0..<layerImages.count {
            if let texture = layerImages[i].texture {
                renderEncoder.setVertexBuffer(vertexBuffers[i], offset: 0, index: 0)
                renderEncoder.setFragmentTexture(texture, index: i)
                
                renderEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: 6,
                    indexType: .uint16,
                    indexBuffer: indexBuffers[i],
                    indexBufferOffset: 0
                )
            }
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

func extractIntValue(from string: String) -> Int? {
    // Split the string by the "_" character
    let components = string.split(separator: "_")
    
    // Take the first component and try to convert it to an Int
    return Int(components.first ?? "")
}
