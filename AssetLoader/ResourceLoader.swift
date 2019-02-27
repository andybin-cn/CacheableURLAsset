//
//  ResourceLoader.swift
//  GradingTest
//
//  Created by Leo on 2016/11/4.
//  Copyright © 2016年 DoSoMi. All rights reserved.
//

import AVFoundation
import MobileCoreServices

class ResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {
    private var originalURL: URL
    private var cache: ResourceLoaderCache
    private var contentType: String?
    private var contentLenght: Int64?
    private var response: URLResponse?
    
    var tasks: NSMutableArray = NSMutableArray(capacity: 2)
    var requests: [Int: AVAssetResourceLoadingRequest] = [:]
    
    private lazy var session: URLSession = { () -> URLSession in
        return URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: self, delegateQueue: OperationQueue.current)
    }()
    
    deinit {
        for task in tasks {
            if let task = task as? URLSessionTask {
                task.cancel()
            }
        }
        dlog("\(type(of: self)) release!")
    }
    
    init(originalURL: URL) {
        self.originalURL = originalURL
        cache = ResourceLoaderCache(identify: originalURL.absoluteString.md5 ?? originalURL.lastPathComponent)
        super.init()
    }
    
    //MARK: - AVAssetResourceLoaderDelegate
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        addLoadingRequest(request: loadingRequest)
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        removeLoadingRequest(request: loadingRequest)
    }
    
    //MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let loadingRequest = requests[dataTask.taskIdentifier], let dataRequest = loadingRequest.dataRequest {
            cache.cacheData(to: dataRequest.currentOffset, data: data)
            dataRequest.respond(with: data)
            
            if dataRequest.currentOffset >= dataRequest.requestedOffset + dataRequest.requestedLength {
                loadingRequest.finishLoading()
                removeLoadingRequest(request: loadingRequest)
            } else {
                if cache.checkHasCache(for: dataRequest.currentOffset, length: 200000) {
                    //已经有200K缓存，直接从缓存读取
                    dlog("dataTask.cancel()")
                    dlog("currentOffset\(dataRequest.currentOffset)")
                    dlog("requestedOffset\(dataRequest.requestedOffset)")
                    dlog("requestedLength\(dataRequest.requestedLength)")
                    removeLoadingRequest(request: loadingRequest)
                    loadDateFromCache(loadingRequest: loadingRequest)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResp = response as? HTTPURLResponse else {
            return
        }
        var contentType = httpResp.allHeaderFields["Content-Type"] as? String ?? "video/mp4"
        let range = httpResp.allHeaderFields["Content-Range"] as? NSString
        let videoLength = range?.components(separatedBy: "/").last ?? "notValue"
        let contentLenght = Int64(videoLength) ?? httpResp.expectedContentLength
        contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, contentType as CFString, nil)?.takeRetainedValue() as? String ?? "public.mpeg-4"
        
        let loadingRequest = requests[dataTask.taskIdentifier]
        loadingRequest?.contentInformationRequest?.contentLength = contentLenght
        loadingRequest?.contentInformationRequest?.contentType = contentType
        loadingRequest?.contentInformationRequest?.isByteRangeAccessSupported = true
        
        cache.initializeCacheFile(with: contentType, contentLength: contentLenght)
        
        completionHandler(.allow)
    }
    
    //MARK: - private functions
    
    func addLoadingRequest(request: AVAssetResourceLoadingRequest) {
        loadDateFromCache(loadingRequest: request)
    }
    
    private func loadDateFromCache(loadingRequest: AVAssetResourceLoadingRequest) {
        if let dataRequest = loadingRequest.dataRequest {
            var requestedOffset = dataRequest.requestedOffset
            if dataRequest.currentOffset > 0 {
                requestedOffset = dataRequest.currentOffset
            }
            let (cacheData, emptyRange) = cache.loadDate(from: requestedOffset, length: Int64(dataRequest.requestedLength))
            if cacheData.count > 0 {
                dataRequest.respond(with: cacheData)
                finishRequestWithCache(request: loadingRequest)
            }
            if emptyRange != nil {
                requestFromServer(for: loadingRequest, range: emptyRange)
            }
        }
    }
    
    func removeLoadingRequest(request: AVAssetResourceLoadingRequest) {
        for task in tasks {
            if let task = task as? URLSessionDataTask {
                if requests[task.taskIdentifier] == request {
                    task.cancel()
                    tasks.remove(task)
                    requests[task.taskIdentifier] = nil
                    return
                }
            }
        }
    }
    
    func invalidateAndCancel() {
        for task in tasks {
            if let task = task as? URLSessionDataTask {
                task.cancel()
                requests[task.taskIdentifier] = nil
            }
        }
        tasks.removeAllObjects()
        session.invalidateAndCancel()
    }
    
    func finishRequestWithCache(request: AVAssetResourceLoadingRequest) {
        if request.dataRequest!.currentOffset >= request.dataRequest!.requestedOffset + request.dataRequest!.requestedLength {
            request.contentInformationRequest?.contentLength = cache.cachesInformation.contentLength
            request.contentInformationRequest?.contentType = cache.cachesInformation.contentType
            request.finishLoading()
        }
    }
    
    func requestFromServer(for request: AVAssetResourceLoadingRequest, range: Range<Int64>? = nil) {
        var httpRequest = URLRequest(url: originalURL)
        if let requestRange = range {
            httpRequest.addValue("bytes=\(requestRange.lowerBound)-\(requestRange.upperBound-1)", forHTTPHeaderField: "Range")
        }
        print("request url: \(httpRequest.url)")
        print("request header: \(httpRequest.allHTTPHeaderFields)")
        let task = session.dataTask(with: httpRequest)
        task.resume()
        tasks.add(task)
        requests[task.taskIdentifier] = request
    }
    
}
