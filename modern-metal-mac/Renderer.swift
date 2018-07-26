//
//  Renderer.swift
//  modern-metal-mac
//


import Foundation
import MetalKit
import simd

struct VertexUniforms {
    var viewProjectionMatrix: float4x4
    var modelMatrix: float4x4
    var normalMatrix: float3x3
}

struct FragmentUniforms {
    var cameraWorldPosition = float3(0, 0, 0)
    var ambientLightColor = float3(0, 0, 0)
    var specularColor = float3(1, 1, 1)
    var specularPower = Float(1)
    var light0 = Light()
    var light1 = Light()
    var light2 = Light()
}

class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var renderPipeline: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let samplerState: MTLSamplerState
    let vertexDescriptor: MDLVertexDescriptor
    let scene: Scene
    
    var time: Float = 0
    var cameraWorldPosition = float3(0, 0, 2)
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    
    static let fishCount = 12
    
    init(view: MTKView, device: MTLDevice) {
        self.device = device
        commandQueue = device.makeCommandQueue()!
        vertexDescriptor = Renderer.buildVertexDescriptor()
        renderPipeline = Renderer.buildPipeline(device: device, view: view, vertexDescriptor: vertexDescriptor)
        samplerState = Renderer.buildSamplerState(device: device)
        depthStencilState = Renderer.buildDepthStencilState(device: device)
        scene = Renderer.buildScene(device: device, vertexDescriptor: vertexDescriptor)
        super.init()
    }
    
    static func buildScene(device: MTLDevice, vertexDescriptor: MDLVertexDescriptor) -> Scene {
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option : Any] = [.generateMipmaps : true, .SRGB : true]
        
        let scene = Scene()
        
        scene.ambientLightColor = float3(0.1, 0.1, 0.1)
        let light0 = Light(worldPosition: float3( 5,  5, 0), color: float3(0.3, 0.3, 0.3))
        let light1 = Light(worldPosition: float3(-5,  5, 0), color: float3(0.3, 0.3, 0.3))
        let light2 = Light(worldPosition: float3( 0, -5, 0), color: float3(0.3, 0.3, 0.3))
        scene.lights = [ light0, light1, light2 ]
        
        let bob = Node(name: "Bob")
        let bobMaterial = Material()
        let bobBaseColorTexture = try? textureLoader.newTexture(name: "bob_baseColor",
                                                                scaleFactor: 1.0,
                                                                bundle: nil,
                                                                options: options)
        bobMaterial.baseColorTexture = bobBaseColorTexture
        bobMaterial.specularPower = 100
        bobMaterial.specularColor = float3(0.8, 0.8, 0.8)
        bob.material = bobMaterial
        
        let bobURL = Bundle.main.url(forResource: "bob", withExtension: "obj")!
        let bobAsset = MDLAsset(url: bobURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        bob.mesh = try! MTKMesh.newMeshes(asset: bobAsset, device: device).metalKitMeshes.first!
        
        scene.rootNode.children.append(bob)
        
        let blubMaterial = Material()
        let blubBaseColorTexture = try? textureLoader.newTexture(name: "blub_baseColor",
                                                                 scaleFactor: 1.0,
                                                                 bundle: nil,
                                                                 options: options)
        blubMaterial.baseColorTexture = blubBaseColorTexture
        blubMaterial.specularPower = 40
        blubMaterial.specularColor = float3(0.8, 0.8, 0.8)
        
        let blubURL = Bundle.main.url(forResource: "blub", withExtension: "obj")!
        let blubAsset = MDLAsset(url: blubURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        let blubMesh = try! MTKMesh.newMeshes(asset: blubAsset, device: device).metalKitMeshes.first!
        
        for i in 1...fishCount {
            let blub = Node(name: "Blub \(i)")
            blub.material = blubMaterial
            blub.mesh = blubMesh
            bob.children.append(blub)
        }
        
        return scene
    }
    
    static func buildVertexDescriptor() -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                            format: .float3,
                                                            offset: 0,
                                                            bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                            format: .float3,
                                                            offset: MemoryLayout<Float>.size * 3,
                                                            bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                            format: .float2,
                                                            offset: MemoryLayout<Float>.size * 6,
                                                            bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        return vertexDescriptor
    }
    
    static func buildSamplerState(device: MTLDevice) -> MTLSamplerState {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        return device.makeSamplerState(descriptor: samplerDescriptor)!
    }
    
    static func buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }
    
    static func buildPipeline(device: MTLDevice, view: MTKView, vertexDescriptor: MDLVertexDescriptor) -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default library from main bundle")
        }
        
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        
        let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state object: \(error)")
        }
    }
    
    
    func update(_ view: MTKView) {
        time += 1 / Float(view.preferredFramesPerSecond)
        
        cameraWorldPosition = float3(0, 0, 2)
        viewMatrix = float4x4(translationBy: -cameraWorldPosition) * float4x4(rotationAbout: float3(1, 0, 0), by: .pi / 6)
        
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 6, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        
        let angle = -time
        scene.rootNode.modelMatrix = float4x4(rotationAbout: float3(0, 1, 0), by: angle)
        
        if let bob = scene.nodeNamed("Bob") {
            bob.modelMatrix = float4x4(translationBy: float3(0, 0.015 * sin(time * 5), 0))
        }
        
        let blubBaseTransform = float4x4(rotationAbout: float3(0, 0, 1), by: -.pi / 2) *
            float4x4(scaleBy: 0.25) *
            float4x4(rotationAbout: float3(0, 1, 0), by: -.pi / 2)
        
        let fishCount = Renderer.fishCount
        for i in 1...fishCount {
            if let blub = scene.nodeNamed("Blub \(i)") {
                let pivotPosition = float3(0.4, 0, 0)
                let rotationOffset = float3(0.4, 0, 0)
                let rotationSpeed = Float(0.3)
                let rotationAngle = 2 * Float.pi * Float(rotationSpeed * time) + (2 * Float.pi / Float(fishCount) * Float(i - 1))
                let horizontalAngle = 2 * .pi / Float(fishCount) * Float(i - 1)
                blub.modelMatrix = float4x4(rotationAbout: float3(0, 1, 0), by: horizontalAngle) *
                    float4x4(translationBy: rotationOffset) *
                    float4x4(rotationAbout: float3(0, 0, 1), by: rotationAngle) *
                    float4x4(translationBy: pivotPosition) *
                blubBaseTransform
            }
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    func draw(in view: MTKView) {
        update(view)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        if let renderPassDescriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable {
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.63, 0.81, 1.0, 1.0)
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            commandEncoder.setFrontFacing(.counterClockwise)
            commandEncoder.setCullMode(.back)
            commandEncoder.setDepthStencilState(depthStencilState)
            commandEncoder.setRenderPipelineState(renderPipeline)
            commandEncoder.setFragmentSamplerState(samplerState, index: 0)
            drawNodeRecursive(scene.rootNode, parentTransform: matrix_identity_float4x4, commandEncoder: commandEncoder)
            commandEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    func drawNodeRecursive(_ node: Node, parentTransform: float4x4, commandEncoder: MTLRenderCommandEncoder) {
        let modelMatrix = parentTransform * node.modelMatrix
        
        if let mesh = node.mesh, let baseColorTexture = node.material.baseColorTexture {
            let viewProjectionMatrix = projectionMatrix * viewMatrix
            var vertexUniforms = VertexUniforms(viewProjectionMatrix: viewProjectionMatrix,
                                                modelMatrix: modelMatrix,
                                                normalMatrix: modelMatrix.normalMatrix)
            commandEncoder.setVertexBytes(&vertexUniforms, length: MemoryLayout<VertexUniforms>.size, index: 1)
            
            var fragmentUniforms = FragmentUniforms(cameraWorldPosition: cameraWorldPosition,
                                                    ambientLightColor: scene.ambientLightColor,
                                                    specularColor: node.material.specularColor,
                                                    specularPower: node.material.specularPower,
                                                    light0: scene.lights[0],
                                                    light1: scene.lights[1],
                                                    light2: scene.lights[2])
            commandEncoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<FragmentUniforms>.size, index: 0)
            
            commandEncoder.setFragmentTexture(baseColorTexture, index: 0)
            
            let vertexBuffer = mesh.vertexBuffers.first!
            commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
            
            for submesh in mesh.submeshes {
                let indexBuffer = submesh.indexBuffer
                commandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                     indexCount: submesh.indexCount,
                                                     indexType: submesh.indexType,
                                                     indexBuffer: indexBuffer.buffer,
                                                     indexBufferOffset: indexBuffer.offset)
            }
        }
        
        for child in node.children {
            drawNodeRecursive(child, parentTransform: modelMatrix, commandEncoder: commandEncoder)
        }
    }
}
