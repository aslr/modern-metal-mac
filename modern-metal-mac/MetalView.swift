//
//  MTKView.swift
//  modern-metal
//


import MetalKit

class MetalView: MTKView {
    
    var renderer: Renderer!
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        
        self.device = MTLCreateSystemDefaultDevice()
        let layer:CAMetalLayer = self.layer as! CAMetalLayer
        layer.framebufferOnly = false
        self.drawableSize.height = self.frame.height
        self.drawableSize.width = self.frame.width
        self.colorPixelFormat = .bgra8Unorm_srgb
        self.depthStencilPixelFormat = .depth32Float
        
        renderer = Renderer(view: self, device: device!)
        self.delegate = renderer
    }
}
