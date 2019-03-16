//
//  GameViewController.swift
//  CubeMapping iOS
//
//  Created by LEE CHUL HYUN on 3/13/19.
//  Copyright © 2019 LEE CHUL HYUN. All rights reserved.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }

        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
        
        let g = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        self.view.addGestureRecognizer(g)
        
    }
    
    @objc func tap(_ sender: Any) {
        renderer.useReflect = !renderer.useReflect
    }
}
