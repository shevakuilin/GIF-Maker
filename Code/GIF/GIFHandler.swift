//
//  GIFHandler.swift
//  GIF
//
//  Created by Christian Lundtofte on 14/03/2017.
//  Copyright © 2017 Christian Lundtofte. All rights reserved.
//

import Foundation
import Cocoa

// Replaces the old '(frames: [GIFFrame], loops:Int, secondsPrFrame: Float)' with a type
// Describes the data necessary to show a gif. Frames, loops, and duration
class GIFRepresentation {
    var frames:[GIFFrame] = [GIFFrame.emptyFrame]
    var loops:Int = GIFHandler.defaultLoops
    
    init(frames: [GIFFrame], loops:Int) {
        self.frames = frames
        self.loops = loops
    }
    
    init() {}
}

// Creates and loads gifs
class GIFHandler {

    // MARK: Constants
    static let errorNotificationName = NSNotification.Name(rawValue: "GIFError")
    static let defaultLoops:Int = 0
    static let defaultFrameDuration:Double = 0.2
    
    // MARK: Loading gifs
    static func loadGIF(with image: NSImage) -> GIFRepresentation {
        
        // Attempt to fetch the number of frames, frame duration, and loop count from the .gif
        guard let bitmapRep = image.representations[0] as? NSBitmapImageRep,
            let frameCount = (bitmapRep.value(forProperty: NSImageFrameCount) as? NSNumber)?.intValue,
            let loopCount = (bitmapRep.value(forProperty: NSImageLoopCount) as? NSNumber)?.intValue else {
                
            print("Error loading gif")
            NotificationCenter.default.post(name: errorNotificationName, object: self, userInfo: ["Error":"Could not load gif. The file does not contain the metadata required for a gif."])
            return GIFRepresentation()
        }

        
        var retFrames:[GIFFrame] = []
        
        // Iterate the frames, set the current frame on the bitmapRep and add this to 'retImages'
        for n in 0 ..< frameCount {
            bitmapRep.setProperty(NSImageCurrentFrame, withValue: NSNumber(value: n))
            
            if let data = bitmapRep.representation(using: .GIF, properties: [:]),
               let img = NSImage(data: data) {
                let frame = GIFFrame(image: img)
                
                if let frameDuration = (bitmapRep.value(forProperty: NSImageCurrentFrameDuration) as? NSNumber)?.doubleValue {
                    frame.duration = frameDuration
                }
                
                retFrames.append(frame)
            }
        }
        
        return GIFRepresentation(frames: retFrames, loops: loopCount)
    }
    
    
    // MARK: Making gifs from iamges
    // Creates and saves a gif
    static func createAndSaveGIF(with frames: [GIFFrame], savePath: URL, loops: Int = GIFHandler.defaultLoops) {
        // Get and save data at 'savePath'
        let data = GIFHandler.createGIFData(with: frames, loops: loops)
        
        do {
            try data.write(to: savePath)
        }
        catch {
            NotificationCenter.default.post(name: errorNotificationName, object: self, userInfo: ["Error":"Could not save file: "+error.localizedDescription])
            print("Error: \(error)")
        }
    }
    
    // Creates and returns an NSImage from given images
    static func createGIF(with frames: [GIFFrame], loops: Int = GIFHandler.defaultLoops) -> NSImage? {
        // Get data and convert to image
        let data = GIFHandler.createGIFData(with: frames, loops: loops)
        let img = NSImage(data: data)
        return img
    }
    
    // Creates NSData from given images
    static func createGIFData(with frames: [GIFFrame], loops: Int = GIFHandler.defaultLoops) -> Data {
        // Loop count
        let loopCountDic = NSDictionary(dictionary: [kCGImagePropertyGIFDictionary:NSDictionary(dictionary: [kCGImagePropertyGIFLoopCount: loops])])
        
        // Number of frames
        let imageCount = frames.filter { (frame) -> Bool in
            return frame.image != nil
        }.count
        
        // Destination (Data object)
        guard let dataObj = CFDataCreateMutable(nil, 0),
            let dst = CGImageDestinationCreateWithData(dataObj, kUTTypeGIF, imageCount, nil) else { fatalError("Can't create gif") }
        CGImageDestinationSetProperties(dst, loopCountDic as CFDictionary) // Set loop count on object
        
        // Add images to destination
        frames.forEach { (frame) in
            guard let image = frame.image else { return }
//            if !Products.store.isProductPurchased(Products.Pro) {
                // Watermark
//            }
            
            if let imageRef = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                // Frame duration
                let frameDurationDic = NSDictionary(dictionary: [kCGImagePropertyGIFDictionary:NSDictionary(dictionary: [kCGImagePropertyGIFDelayTime: frame.duration])])
                
                // Add image
                CGImageDestinationAddImage(dst, imageRef, frameDurationDic as CFDictionary)
            }
        }
        

        // Close, cast as data and return
        let _ = CGImageDestinationFinalize(dst)
        let retData = dataObj as Data
        return retData
    }
    
    
    // MARK: Helper functions for gifs
    // Naive method for determining whether something is an animated gif
    static func isAnimatedGIF(_ image: NSImage) -> Bool {
        // Attempt to fetch the number of frames, frame duration, and loop count from the .gif
        guard let bitmapRep = image.representations[0] as? NSBitmapImageRep,
            let frameCount = (bitmapRep.value(forProperty: NSImageFrameCount) as? NSNumber)?.intValue,
            let _ = (bitmapRep.value(forProperty: NSImageLoopCount) as? NSNumber)?.intValue,
            let _ = (bitmapRep.value(forProperty: NSImageCurrentFrameDuration) as? NSNumber)?.floatValue else {
            return false
        }

        return frameCount > 1 // We have loops, duration and everything, and there's more than 1 frame, it's probably a gif
    }
    
    
    // Adds a watermark to all images in the gif
    // (Sorry..)
    static func addWatermark(images: [NSImage], watermark: String) -> [NSImage] {
        guard let font = NSFont(name: "Helvetica", size: 14) else { return images }
        var returnImages:[NSImage] = []
        
        let attrs:[String:Any] = [NSForegroundColorAttributeName: NSColor.white, NSFontAttributeName: font, NSStrokeWidthAttributeName: -3, NSStrokeColorAttributeName: NSColor.black]
        
        for image in images {
            // We need to create a 'copy' of the imagerep, as we need 'isPlanar' to be false in order to draw on it
            // Thanks http://stackoverflow.com/a/13617013 and https://gist.github.com/randomsequence/b9f4462b005d0ced9a6c
            let tmpRep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            guard let imgRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                             pixelsWide: tmpRep.pixelsWide,
                             pixelsHigh: tmpRep.pixelsHigh,
                             bitsPerSample: 8,
                             samplesPerPixel: 4,
                             hasAlpha: true,
                             isPlanar: false,
                             colorSpaceName: NSCalibratedRGBColorSpace,
                             bytesPerRow: 0,
                             bitsPerPixel: 0) else { print("Error image"); continue }
            
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.setCurrent(NSGraphicsContext.init(bitmapImageRep: imgRep))
            
            // Draw image and string
            image.draw(at: NSPoint.zero, from: NSZeroRect, operation: .copy, fraction: 1.0)
            watermark.draw(at: NSPoint(x: 5, y: 5), withAttributes: attrs)
            
            NSGraphicsContext.restoreGraphicsState()
            
            let data = imgRep.representation(using: .GIF, properties: [:])
            let newImg = NSImage(data: data!)
            returnImages.append(newImg!)
        }
        
        return returnImages
    }
}
