//
//  ResourceLoaderCache.swift
//  GradingTest
//
//  Created by Leo on 2016/11/4.
//  Copyright © 2016年 DoSoMi. All rights reserved.
//

class ResourceLoaderCache {
    var fileUrl: URL
    var fileHandle: FileHandle?
    
    var cachesInformation: ResourceLoaderCachesInformation
    var serialQueue: DispatchQueue

    init(identify: String) {
        fileUrl = URL(fileURLWithPath: "\(NSHomeDirectory())/Documents/videoCaches/\(identify).temp")
        cachesInformation = ResourceLoaderCachesInformation(fileUrl: fileUrl.appendingPathExtension("segments"))
        serialQueue = DispatchQueue(label: "ResourceLoaderCache.FileWriter.SerialQueue")
        dlog("ResourceLoaderCache fileUrl: \(fileUrl.absoluteString)")
    }
    
    deinit {
        fileHandle?.closeFile()
        dlog("\(type(of: self)) release!")
    }
    
    func loadDate(from offset: Int64, length: Int64) -> (Data, Range<Int64>?) {
        if let cacheDataRange = cachesInformation.cachedRange(for: offset..<offset+length) {
            if let data = try? Data(contentsOf: fileUrl, options: Data.ReadingOptions.dataReadingMapped), Int64(data.count) >= cacheDataRange.dateRange.upperBound {
                let upperBound = min(cacheDataRange.dateRange.upperBound, Int64(data.count) - offset)
                let range = Range<Data.Index>.init(uncheckedBounds: (Data.Index(offset), Data.Index(upperBound)))
                return (data.subdata(in: range), cacheDataRange.emptyRange)
            }
        }
        return (Data(), offset..<offset+length)
    }
    
    func cacheData(to offset: Int64, data: Data) {
        serialQueue.async { [weak self] in
            self?.fileHandle?.seek(toFileOffset: UInt64(offset))
            self?.fileHandle?.write(data)
            self?.cachesInformation.append(segmentRange: offset..<offset+Int64(data.count))
        }
    }
    
    func checkHasCache(for offset: Int64, length: Int64) -> Bool {
        if let cacheDataRange = cachesInformation.cachedRange(for: offset..<offset+length), cacheDataRange.emptyRange == nil {
            return true
        }
        return false
    }
    
    func initializeCacheFile(with contentType: String, contentLength: Int64) {
        if fileHandle == nil {
            cachesInformation.contentLength = contentLength
            cachesInformation.contentType = contentType
            
            try? FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            if !FileManager.default.fileExists(atPath: fileUrl.path) {
                FileManager.default.createFile(atPath: fileUrl.path, contents: nil, attributes: [FileAttributeKey.size.rawValue : contentLength])
            }
            fileHandle = try? FileHandle(forWritingTo: fileUrl)
            fileHandle?.truncateFile(atOffset: UInt64(contentLength))
        }
    }
}


class ResourceLoaderCachesInformation {
    var ranges: [Range<Int64>] = [] {
        didSet {
            save()
        }
    }
    
    fileprivate(set) var contentLength: Int64 {
        didSet {
            save()
        }
    }
    fileprivate(set) var contentType: String {
        didSet {
            save()
        }
    }
    
    var fileUrl: URL
    init(fileUrl: URL) {
        self.fileUrl = fileUrl
        let dic = NSDictionary(contentsOf: fileUrl)
        if let array = dic?["CachedSegmentRanges"] as? NSArray {
            for item in array {
                if let itemDic = item as? NSDictionary, let lowerBound = itemDic["lowerBound"] as? Int64, let upperBound = itemDic["upperBound"] as? Int64 {
                    ranges.append(Range<Int64>(uncheckedBounds: (lowerBound, upperBound)))
                }
            }
        }
        contentLength = dic?["contentLength"] as? Int64 ?? 0
        contentType = dic?["contentType"] as? String ?? "public.mpeg-4"
    }
    
    func append(segmentRange: Range<Int64>) {
        if segmentRange.upperBound > contentLength {
            contentLength = segmentRange.upperBound
        }
        if ranges.count == 0 {
            ranges.append(segmentRange)
            return
        }
        var lastMergeRange: Range<Int64>?
        for (index, range) in ranges.enumerated() {
            if let segmentRange = lastMergeRange {
                let clamp = range.clamped(to: segmentRange)
                if !clamp.isEmpty || range.upperBound == segmentRange.lowerBound || range.lowerBound == segmentRange.upperBound {
                    let lowerBound = min(range.lowerBound, segmentRange.lowerBound)
                    let upperBound = max(range.upperBound, segmentRange.upperBound)
                    let mergeRange = Range<Int64>(uncheckedBounds: (lowerBound, upperBound))
                    ranges.replaceSubrange(Range<Int>(uncheckedBounds: (index-1, index+1)), with: [mergeRange])
                    lastMergeRange = mergeRange
                    continue
                }
                return
            }
            if segmentRange.upperBound < range.lowerBound {
                ranges.insert(segmentRange, at: index)
                return
            }
            if index == ranges.count-1 && segmentRange.lowerBound > range.upperBound {
                ranges.append(segmentRange)
                return
            }
            let clamp = range.clamped(to: segmentRange)
            if !clamp.isEmpty || range.upperBound == segmentRange.lowerBound || range.lowerBound == segmentRange.upperBound {
                let lowerBound = min(range.lowerBound, segmentRange.lowerBound)
                let upperBound = max(range.upperBound, segmentRange.upperBound)
                let mergeRange = Range<Int64>(uncheckedBounds: (lowerBound, upperBound))
                ranges.replaceSubrange(Range<Int>(uncheckedBounds: (index, index+1)), with: [mergeRange])
                lastMergeRange = mergeRange
                continue
            }
        }
    }
    
    func cachedRange(for requestRange: Range<Int64>) -> CacheRangeDate? {
        for (index, range) in ranges.enumerated() {
            let clamp = range.clamped(to: requestRange)
            if !clamp.isEmpty && clamp.lowerBound == requestRange.lowerBound {
                var emptyRange: Range<Int64>? = nil
                if clamp.upperBound < requestRange.upperBound {
                    if ranges.count - 1 > index {
                        let nextRange = ranges[index+1]
                        emptyRange = clamp.upperBound..<min(nextRange.lowerBound, contentLength)
                    } else {
                        emptyRange = clamp.upperBound..<contentLength
                    }
                    
                }
                return CacheRangeDate(dateRange: clamp, emptyRange: emptyRange)
            }
        }
        return nil
    }
    
    func save() {
        let array = NSMutableArray(capacity: ranges.count)
        for range in ranges {
            array.add(["lowerBound": range.lowerBound, "upperBound":range.upperBound])
        }
        let dic = NSMutableDictionary()
        dic["CachedSegmentRanges"] = array
        dic["contentLength"] = contentLength
        dic["contentType"] = contentType
        dic.write(to: fileUrl, atomically: true)
    }
    
    struct CacheRangeDate {
        var dateRange: Range<Int64>
        var emptyRange: Range<Int64>?
    }
}

