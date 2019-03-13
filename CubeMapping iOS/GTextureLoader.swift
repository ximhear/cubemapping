//
//  GTextureLoader.swift
//  TextureMapping iOS
//
//  Created by gzonelee on 08/03/2019.
//  Copyright © 2019 LEE CHUL HYUN. All rights reserved.
//

import UIKit
import Metal
import CoreGraphics

class GTextureLoader {
    
    private init() {
        
    }
    
    static var `default`: GTextureLoader = {
        let loader = GTextureLoader()
        return loader
    
    }()
        
    func texture2DWithImage(named imageName: String, mipmapped: Bool, commandQueue: MTLCommandQueue) -> MTLTexture? {

        guard let image = UIImage(named: imageName) else {
            return nil
        }
    
        let imageSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let bytesPerPixel: UInt = 4
        let bytesPerRow: UInt = bytesPerPixel * UInt(imageSize.width)
        
        let imageData = dataForImage(image)
    
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: Int(imageSize.width), height: Int(imageSize.height), mipmapped: mipmapped)
        textureDescriptor.usage = .shaderRead
        let texture = commandQueue.device.makeTexture(descriptor: textureDescriptor)
        texture?.label = imageName
        
        let region = MTLRegionMake2D(0, 0, Int(imageSize.width), Int(imageSize.height))
        texture?.replace(region: region, mipmapLevel: 0, withBytes: imageData, bytesPerRow: Int(bytesPerRow))
        
        imageData.deallocate()
    
        if mipmapped, let texture = texture {
            generateMipmapsForTexture(texture: texture, queue: commandQueue)
        }
        
        return texture;
    }
    
    func dataForImage(_ image: UIImage) -> UnsafeMutablePointer<UInt8> {
        let imageRef = image.cgImage!
        let width: Int = imageRef.width
        let height: Int = imageRef.height
        let space = CGColorSpaceCreateDeviceRGB()
        
        
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: height * width * 4)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        let context = CGContext(data: pointer,
                                           width: width,
                                           height: height,
                                           bitsPerComponent: bitsPerComponent,
                                           bytesPerRow: bytesPerRow,
                                           space: space,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        
//        context?.translateBy(x: 0, y: CGFloat(height))
//        context?.scaleBy(x: 1, y: -1)

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context?.draw(imageRef, in: imageRect)
        
        return pointer
    }
    
    func generateMipmapsForTexture(texture: MTLTexture, queue: MTLCommandQueue) -> Void {
        let commandBuffer = queue.makeCommandBuffer()
        let blitEncoder = commandBuffer?.makeBlitCommandEncoder()
        blitEncoder?.generateMipmaps(for: texture)
        blitEncoder?.endEncoding()
        commandBuffer?.commit()

        commandBuffer?.waitUntilCompleted()
    }
}

