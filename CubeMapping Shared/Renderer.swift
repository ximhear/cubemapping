//
//  Renderer.swift
//  CubeMapping Shared
//
//  Created by LEE CHUL HYUN on 3/13/19.
//  Copyright © 2019 LEE CHUL HYUN. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedEnvironmentUniformsSize = (MemoryLayout<EnvironmentUniforms>.size & ~0xFF) + 0x100
let alignedCubeUniformsSize = (MemoryLayout<CubeUniforms>.size & ~0xFF) + 0x100
let alignedPerInstanceUniformsSize = (MemoryLayout<PerInstanceUniforms>.size & ~0xFF) + 0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    var dynamicEnvironmentUniformBuffer: MTLBuffer
    var dynamicCubeUniformBuffer: MTLBuffer
    var dynamicPerInstanceUniformBuffer: MTLBuffer
    
    var pipelineState: MTLRenderPipelineState
    var environmentPipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var environmentUniformBufferOffset = 0
    var environmentUniformBufferIndex = 0

    var cubeUniformBufferOffset = 0
    var cubeUniformBufferIndex = 0

    var perInstanceUniformBufferOffset = 0
    var perInstanceUniformBufferIndex = 0

    var environmentUniforms: UnsafeMutablePointer<EnvironmentUniforms>
    var cubeUniforms: UnsafeMutablePointer<CubeUniforms>
    var perInstanceUniforms: UnsafeMutablePointer<PerInstanceUniforms>

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    var rotation: Float = 0
    
    var cubeTexture: MTLTexture!
    var samplerState: MTLSamplerState!
    
    var vertices: [Float] = []
    var indices: [UInt16] = []
    var indexCount: Int = 0
    var vertexBuffer: MTLBuffer!
    var indexBuffer: MTLBuffer!

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let environmentUniformBufferSize = alignedEnvironmentUniformsSize * maxBuffersInFlight
        let cubeUniformBufferSize = alignedCubeUniformsSize * maxBuffersInFlight
        let perInstanceUniformBufferSize = alignedPerInstanceUniformsSize * maxBuffersInFlight

        guard let environmentBuffer = self.device.makeBuffer(length:environmentUniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        dynamicEnvironmentUniformBuffer = environmentBuffer

        guard let cubeBuffer = self.device.makeBuffer(length:cubeUniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        dynamicCubeUniformBuffer = cubeBuffer

        guard let perInstanceBuffer = self.device.makeBuffer(length:perInstanceUniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        dynamicPerInstanceUniformBuffer = perInstanceBuffer
        
        self.dynamicEnvironmentUniformBuffer.label = "EnvironmentUniformBuffer"
        self.dynamicCubeUniformBuffer.label = "CubeUniformBuffer"
        self.dynamicPerInstanceUniformBuffer.label = "PerInstanceUniformBuffer"

        environmentUniforms = UnsafeMutableRawPointer(dynamicEnvironmentUniformBuffer.contents()).bindMemory(to:EnvironmentUniforms.self, capacity:1)
        cubeUniforms = UnsafeMutableRawPointer(dynamicCubeUniformBuffer.contents()).bindMemory(to:CubeUniforms.self, capacity:1)
        perInstanceUniforms = UnsafeMutableRawPointer(dynamicPerInstanceUniformBuffer.contents()).bindMemory(to:PerInstanceUniforms.self, capacity:1)

        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        let mtlVertexDescriptor1 = Renderer.buildEnvironmentVertexDescriptor()
        do {
            environmentPipelineState = try Renderer.buildEnvironmentRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor1)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        
        cubeTexture = GTextureLoader.default.textureCubeWithImages(["px", "nx", "py", "ny", "pz", "nz"], device: device)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest;
        samplerDescriptor.magFilter = .linear;
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)

        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) else { return nil }
        depthState = state
        
        super.init()
        
        let divideCount = 10
        // px
        let mesh = divide(startx: -0.5, endx: 0.5, starty: -0.5, endy: 0.5, count: divideCount)
        for points in mesh {
            let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
                return (0.5, point.0, point.1, 1, 0, 0)
            }
            for pt in pts {
                vertices.append(pt.0)
                vertices.append(pt.1)
                vertices.append(pt.2)
                vertices.append(pt.3)
                vertices.append(pt.4)
                vertices.append(pt.5)
            }
        }
        for y in 0..<divideCount {
            for x in 0..<divideCount {
                indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
                indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
                indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
                indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
                indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
                indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
            }
        }
        vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Float>.stride * vertices.count, options: .storageModeShared)
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
    }
    
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Creete a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices
        
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[0].offset = 0
        mtlVertexDescriptor.attributes[0].bufferIndex = 0
        
        mtlVertexDescriptor.attributes[1].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[1].offset = 12
        mtlVertexDescriptor.attributes[1].bufferIndex = 0
        
        mtlVertexDescriptor.layouts[0].stride = 24
        mtlVertexDescriptor.layouts[0].stepRate = 1
        mtlVertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    class func buildEnvironmentVertexDescriptor() -> MTLVertexDescriptor {
        // Creete a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices
        
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[0].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[0].offset = 0
        mtlVertexDescriptor.attributes[0].bufferIndex = 0
        
        mtlVertexDescriptor.layouts[0].stride = 12
        mtlVertexDescriptor.layouts[0].stepRate = 1
        mtlVertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertex_reflect")
//        let vertexFunction = library?.makeFunction(name: "vertex_refract")
        let fragmentFunction = library?.makeFunction(name: "fragment_cube_lookup")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    class func buildEnvironmentRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "environmentVertexShader")
        let fragmentFunction = library?.makeFunction(name: "environmentFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        environmentUniformBufferIndex = (environmentUniformBufferIndex + 1) % maxBuffersInFlight
        environmentUniformBufferOffset = alignedEnvironmentUniformsSize * environmentUniformBufferIndex

        cubeUniformBufferIndex = (cubeUniformBufferIndex + 1) % maxBuffersInFlight
        cubeUniformBufferOffset = alignedCubeUniformsSize * cubeUniformBufferIndex

        perInstanceUniformBufferIndex = (perInstanceUniformBufferIndex + 1) % maxBuffersInFlight
        perInstanceUniformBufferOffset = alignedPerInstanceUniformsSize * perInstanceUniformBufferIndex
        
        environmentUniforms = UnsafeMutableRawPointer(dynamicEnvironmentUniformBuffer.contents() + environmentUniformBufferOffset).bindMemory(to:EnvironmentUniforms.self, capacity:1)
        cubeUniforms = UnsafeMutableRawPointer(dynamicCubeUniformBuffer.contents() + cubeUniformBufferOffset).bindMemory(to:CubeUniforms.self, capacity:1)
        perInstanceUniforms = UnsafeMutableRawPointer(dynamicPerInstanceUniformBuffer.contents() + perInstanceUniformBufferOffset).bindMemory(to:PerInstanceUniforms.self, capacity:1)
    }
    
    private func updateGameStateCenter() {
        /// Update any game state before rendering
        
        cubeUniforms[0].projectionMatrix = projectionMatrix

        let rotationAxis = float3(1, 1, 0.3)
//        rotation = radians_from_degrees(45)
        let modelMatrix = simd_mul(matrix4x4_rotation(radians: rotation, axis: rotationAxis), matrix_float4x4(diagonal: [2, 2, 2, 1]))
//        let modelMatrix = matrix4x4_rotation(radians: rotation, axis: rotationAxis)
        let viewMatrix = matrix4x4_translation(0.0, 0.0, 4.0)
        
        cubeUniforms[0].viewMatrix = viewMatrix
        cubeUniforms[0].modelMatrix = modelMatrix
        cubeUniforms[0].worldCameraPosition = float4(0.0, 0.0, -4.0, 1)
        
        for x in 0..<6 {
            if x == 0 { // px
                perInstanceUniforms[x].modelMatrix = modelMatrix
            }
            else if x == 1 { // nx
                perInstanceUniforms[x].modelMatrix = simd_mul(modelMatrix, matrix4x4_rotation(radians: radians_from_degrees(180), axis: float3(0, 1, 0)))
            }
            else if x == 2 { // pz
                perInstanceUniforms[x].modelMatrix = simd_mul(modelMatrix, matrix4x4_rotation(radians: radians_from_degrees(-90), axis: float3(0, 1, 0)))
            }
            else if x == 3 { // nz
                perInstanceUniforms[x].modelMatrix = simd_mul(modelMatrix, matrix4x4_rotation(radians: radians_from_degrees(90), axis: float3(0, 1, 0)))
            }
            else if x == 4 { // py
                perInstanceUniforms[x].modelMatrix = simd_mul(modelMatrix, matrix4x4_rotation(radians: radians_from_degrees(-90), axis: float3(0, 0, 1)))
            }
            else if x == 5 { // ny
                perInstanceUniforms[x].modelMatrix = simd_mul(modelMatrix, matrix4x4_rotation(radians: radians_from_degrees(90), axis: float3(0, 0, 1)))
            }
            perInstanceUniforms[x].normalMatrix = perInstanceUniforms[x].modelMatrix.inverse.transpose
        }
        rotation += 0.005
    }

    private func updateGameStateEnvironment() {
        /// Update any game state before rendering
        
        environmentUniforms[0].projectionMatrix = projectionMatrix

        let modelMatrix = matrix_float4x4(diagonal: [1, 1, 1, 1])
        let viewMatrix = matrix4x4_translation(0.0, 0.0, 4.0)
        environmentUniforms[0].viewMatrix = viewMatrix
        environmentUniforms[0].modelMatrix = modelMatrix
    }

    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                /// Final pass rendering code here
                renderEncoder.label = "Primary Render Encoder"
                
                renderEncoder.pushDebugGroup("Draw Box")
                
                renderEncoder.setCullMode(.back)
                
                renderEncoder.setDepthStencilState(depthState)
                
                
                
                
                renderEncoder.setFrontFacing(.clockwise)
                
                self.updateGameStateEnvironment()

                renderEncoder.setRenderPipelineState(environmentPipelineState)
                
                renderEncoder.setVertexBuffer(dynamicEnvironmentUniformBuffer, offset:environmentUniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                
                renderEncoder.setFragmentSamplerState(samplerState, index: 0)
                renderEncoder.setFragmentTexture(cubeTexture, index: 0)

                let environmentVertices: [Float] = [
                    // px
                    0.5, 0.5, -0.5,
                    0.5, -0.5, -0.5,
                    0.5, -0.5, 0.5,
                    0.5, 0.5, 0.5,
                    
                    // nx
                    -0.5, 0.5, 0.5,
                    -0.5, -0.5, 0.5,
                    -0.5, -0.5, -0.5,
                    -0.5, 0.5, -0.5,
                    
                    // py
                    -0.5, 0.5, 0.5,
                    -0.5, 0.5, -0.5,
                    0.5, 0.5, -0.5,
                    0.5, 0.5, 0.5,
                    
                    // ny
                    -0.5, -0.5, -0.5,
                    -0.5, -0.5, 0.5,
                    0.5, -0.5, 0.5,
                    0.5, -0.5, -0.5,
                    
                    // pz
                    0.5, 0.5, 0.5,
                    0.5, -0.5, 0.5,
                    -0.5, -0.5, 0.5,
                    -0.5, 0.5, 0.5,
                    
                    // nz
                    -0.5, 0.5, -0.5,
                    -0.5, -0.5, -0.5,
                    0.5, -0.5, -0.5,
                    0.5, 0.5, -0.5,
                    ].map { $0 * 10 }
                
                var environmentIndices: [UInt16] = []
                for y in 0..<6 {
                    let x = UInt16(y)
                    environmentIndices.append(0 + 4 * x)
                    environmentIndices.append(1 + 4 * x)
                    environmentIndices.append(2 + 4 * x)
                    environmentIndices.append(0 + 4 * x)
                    environmentIndices.append(2 + 4 * x)
                    environmentIndices.append(3 + 4 * x)
                }

                renderEncoder.setVertexBytes(environmentVertices, length: MemoryLayout<Float>.stride * environmentVertices.count, index: 0)
                
                let environmentIndexCount = environmentIndices.count
                
                let environmentIndexBuffer = device.makeBuffer(bytes: environmentIndices, length: MemoryLayout<UInt16>.stride * environmentIndexCount, options: .storageModeShared)

                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                    indexCount: environmentIndexCount ,
                                                    indexType: .uint16,
                                                    indexBuffer: environmentIndexBuffer!,
                                                    indexBufferOffset: 0)




                renderEncoder.setFrontFacing(.counterClockwise)

                self.updateGameStateCenter()

                renderEncoder.setRenderPipelineState(pipelineState)
                
                renderEncoder.setVertexBuffer(dynamicCubeUniformBuffer, offset:cubeUniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                renderEncoder.setVertexBuffer(dynamicPerInstanceUniformBuffer, offset:perInstanceUniformBufferOffset, index: BufferIndex.perInstanceUniforms.rawValue)
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.meshPositions.rawValue)

                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                    indexCount: indexCount ,
                                                    indexType: .uint16,
                                                    indexBuffer: indexBuffer!,
                                                    indexBufferOffset: 0,
                                                    instanceCount: 6)

//                let divideCount = 10
//                var vertices: [Float] = []
//
//                // px
//                var mesh = divide(startx: -0.5, endx: 0.5, starty: -0.5, endy: 0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (0.5, point.0, point.1, 1, 0, 0)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                var indices: [UInt16] = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                var indexCount = indices.count
//                var indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)
//
//                // nx
//                vertices = []
//                mesh = divide(startx: -0.5, endx: 0.5, starty: 0.5, endy: -0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (-0.5, point.0, point.1, -1, 0, 0)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                indices = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                indexCount = indices.count
//                indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)
//
//                // py
//                vertices = []
//                mesh = divide(startx: -0.5, endx: 0.5, starty: -0.5, endy: 0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (point.1, 0.5, point.0, 0, 1, 0)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                indices = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                indexCount = indices.count
//                indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)
//
//                // ny
//                vertices = []
//                mesh = divide(startx: -0.5, endx: 0.5, starty: 0.5, endy: -0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (point.1, -0.5, point.0, 0, -1, 0)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                indices = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                indexCount = indices.count
//                indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)
//
//                // pz
//                vertices = []
//                mesh = divide(startx: 0.5, endx: -0.5, starty: -0.5, endy: 0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (point.1, point.0, 0.5, 0, 0, 1)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                indices = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                indexCount = indices.count
//                indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)
//
//                // nz
//                vertices = []
//                mesh = divide(startx: -0.5, endx: 0.5, starty: 0.5, endy: -0.5, count: divideCount)
//                for points in mesh {
//                    let pts = points.map { (point) -> (Float, Float, Float, Float, Float, Float) in
//                        return (point.0, point.1, -0.5, 0, 0, -1)
//                    }
//                    for pt in pts {
//                        vertices.append(pt.0)
//                        vertices.append(pt.1)
//                        vertices.append(pt.2)
//                        vertices.append(pt.3)
//                        vertices.append(pt.4)
//                        vertices.append(pt.5)
//                    }
//                }
//                renderEncoder.setVertexBytes(vertices, length: MemoryLayout<Float>.stride * vertices.count, index: 0)
//                indices = []
//                for y in 0..<divideCount {
//                    for x in 0..<divideCount {
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 0))
//                        indices.append(UInt16((y + 1) * (divideCount + 1) + x + 1))
//                        indices.append(UInt16((y + 0) * (divideCount + 1) + x + 1))
//                    }
//                }
//                indexCount = indices.count
//                indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.stride * indexCount, options: .storageModeShared)
//                renderEncoder.drawIndexedPrimitives(type: .triangle,
//                                                    indexCount: indexCount ,
//                                                    indexType: .uint16,
//                                                    indexBuffer: indexBuffer!,
//                                                    indexBufferOffset: 0)

                renderEncoder.popDebugGroup()
                
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func divide(startx: Float, endx: Float, starty: Float, endy: Float, count: Int) -> [[(Float, Float)]] {
        
        let offsetx = (endx - startx) / Float(count)
        let offsety = (endy - starty) / Float(count)
        
        var result = [[(Float, Float)]]()
        
        for y in 0..<(count + 1) {
            var xs = [(Float, Float)]()
            for x in 0..<(count + 1) {
                xs.append((startx + offsetx * Float(x), starty + offsety * Float(y)))
            }
            result.append(xs)
        }

        return result
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_left_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: float3) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func matrix_perspective_left_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (farZ - nearZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, 1),
                                         vector_float4( 0,  0, zs * -nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
