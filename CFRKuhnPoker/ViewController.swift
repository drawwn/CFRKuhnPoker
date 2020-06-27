//
//  ViewController.swift
//  CFRKuhnPoker
//
//  Created by Daniel McLean on 6/27/20.
//  Copyright © 2020 Daniel McLean. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let cfrKuhn = CFRKuhn()
        cfrKuhn.run(numIters: 100000)
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

