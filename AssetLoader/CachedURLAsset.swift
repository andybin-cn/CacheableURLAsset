//
//  CachedURLAsset.swift
//  GradingTest
//
//  Created by Leo on 2016/11/2.
//  Copyright © 2016年 DoSoMi. All rights reserved.
//

import AVFoundation
import MobileCoreServices

class CachedURLAsset: AVURLAsset {
    private var customeResourceLoader: ResourceLoader
    
    deinit {
        resourceLoader.setDelegate(nil, queue: nil)
        customeResourceLoader.invalidateAndCancel()
        dlog("\(type(of: self)) release!")
    }
    
    override init(url: URL, options: [String : Any]? = nil) {
        var customURL = URLComponents(url: url, resolvingAgainstBaseURL: false)
        customURL?.scheme = "customscheme"
        customeResourceLoader = ResourceLoader(originalURL: url)
        super.init(url: customURL?.url ?? url, options: options)
        resourceLoader.setDelegate(customeResourceLoader, queue: DispatchQueue.main)
    }
}
