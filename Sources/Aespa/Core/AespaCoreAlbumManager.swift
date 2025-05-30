//
//  AespaCoreAlbumManager.swift
//  
//
//  Created by 이영빈 on 2023/06/02.
//

import Photos

/// Retreive the video(url) from `FileManager` based local storage
/// and add the video to the pre-defined album roll
class AespaCoreAlbumManager: NSObject {
    // Dependencies
    private let cachingProxy: AssetCachingProxy
    private let photoLibrary: PHPhotoLibrary
    private let albumName: String
    private let videoAssetEventSubject: AssetEventSubject
    private let photoAssetEventSubject: AssetEventSubject
    
    private var album: PHAssetCollection?
    private var latestVideoFetchResult: PHFetchResult<PHAsset>?
    private var latestPhotoFetchResult: PHFetchResult<PHAsset>?
    private var isProcessingUserCapture: Bool = false
    private var hasInitialized: Bool = false
    
    convenience init(
        albumName: String,
        videoAssetEventSubject: AssetEventSubject,
        photoAssetEventSubject: AssetEventSubject
    ) {
        let photoLibrary = PHPhotoLibrary.shared()
        let cachingProxy = AssetCachingProxy()
        self.init(
            albumName: albumName,
            cachingProxy,
            photoLibrary,
            videoAssetEventSubject,
            photoAssetEventSubject
        )
    }

    init(
        albumName: String,
        _ cachingProxy: AssetCachingProxy,
        _ photoLibrary: PHPhotoLibrary,
        _ videoAssetEventSubject: AssetEventSubject,
        _ photoAssetEventSubject: AssetEventSubject
    ) {
        self.cachingProxy = cachingProxy
        self.albumName = albumName
        self.photoLibrary = photoLibrary
        self.videoAssetEventSubject = videoAssetEventSubject
        self.photoAssetEventSubject = photoAssetEventSubject
        
        super.init()
    }

    func run<T: AespaAssetProcessing>(processor: T) async throws {
        guard
            case .authorized = await photoLibrary.requestAuthorization(for: .addOnly)
        else {
            let error = AespaError.album(reason: .unabledToAccess)
            Logger.log(error: error)
            throw error
        }

        if let album {
            ensureLatestFetchResults(for: album)
            try await processor.process(photoLibrary, album)
        } else {
            album = try AlbumImporter.getAlbum(name: albumName, in: photoLibrary)
            try await run(processor: processor)
        }
    }
    
    func run<T: AespaAssetLoading>(loader: T) async throws -> T.ReturnType {
        guard
            case .authorized = await photoLibrary.requestAuthorization(for: .readWrite)
        else {
            let error = AespaError.album(reason: .unabledToAccess)
            Logger.log(error: error)
            throw error
        }

        if let album {
            ensureLatestFetchResults(for: album)
            return try loader.loadAssets(photoLibrary, album)
        } else {
            album = try AlbumImporter.getAlbum(name: albumName, in: photoLibrary)
            return try await run(loader: loader)
        }
    }
}

extension AespaCoreAlbumManager {
    func addToAlbum(filePath: URL) async throws {
        isProcessingUserCapture = true
        defer { isProcessingUserCapture = false }
        
        let processor = VideoAssetAdditionProcessor(filePath: filePath)
        try await run(processor: processor)
    }

    func addToAlbum(imageData: Data) async throws {
        isProcessingUserCapture = true
        defer { isProcessingUserCapture = false }
        
        let processor = PhotoAssetAdditionProcessor(imageData: imageData)
        try await run(processor: processor)
    }
    
    func fetchPhotoFile(limit: Int) async -> [PhotoAsset] {
        let loader = AssetLoader(limit: limit, assetType: .image)

        do {
            let assets = try await run(loader: loader)
            return await cachingProxy.fetchPhoto(assets)
        } catch let error {
            Logger.log(error: error)
            return []
        }
    }
    
    func fetchVideoFile(limit: Int) async -> [VideoAsset] {
        let processor = AssetLoader(limit: limit, assetType: .video)
        
        do {
            let assets = try await run(loader: processor)
            return await cachingProxy.fetchVideo(assets)
        } catch let error {
            Logger.log(error: error)
            return []
        }
    }
}

extension AespaCoreAlbumManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        if let latestVideoFetchResult {
            handleChange(changeInstance, with: latestVideoFetchResult, for: .video)
        }
        
        if let latestPhotoFetchResult {
            handleChange(changeInstance, with: latestPhotoFetchResult, for: .image)
        }
    }
    
    private func ensureLatestFetchResults(for album: PHAssetCollection) {
        // Only send initial load events if this is truly the first initialization
        let shouldSendInitialEvents = !hasInitialized && (latestVideoFetchResult == nil || latestPhotoFetchResult == nil)
        
        if latestVideoFetchResult == nil {
            latestVideoFetchResult = try? AssetLoader(limit: 0, assetType: .video).laodFetchResult(photoLibrary, album)
            if shouldSendInitialEvents,
               let fetchResult = latestVideoFetchResult,
               fetchResult.count > 0 {
                let indexSet = IndexSet(integersIn: 0..<fetchResult.count)
                let assets = fetchResult.objects(at: indexSet)
                videoAssetEventSubject.send(.added(Array(assets), source: .initialLoad))
            }
            observePhotoLibraryChanges(album: album)
        }
        
        if latestPhotoFetchResult == nil {
            latestPhotoFetchResult = try? AssetLoader(limit: 0, assetType: .image).laodFetchResult(photoLibrary, album)
            if shouldSendInitialEvents,
               let fetchResult = latestPhotoFetchResult,
               fetchResult.count > 0 {
                let indexSet = IndexSet(integersIn: 0..<fetchResult.count)
                let assets = fetchResult.objects(at: indexSet)
                photoAssetEventSubject.send(.added(Array(assets), source: .initialLoad))
            }
            observePhotoLibraryChanges(album: album)
        }
        
        // Mark as initialized after first setup
        if shouldSendInitialEvents {
            hasInitialized = true
        }
    }
    
    private func observePhotoLibraryChanges(album: PHAssetCollection) {
        photoLibrary.register(self)
    }
    
    private func handleChange(
        _ changeInstance: PHChange,
        with fetchResult: PHFetchResult<PHAsset>,
        for assetType: PHAssetMediaType
    ) {
        if let details = changeInstance.changeDetails(for: fetchResult) {
            switch assetType {
            case .video:
                self.latestVideoFetchResult = details.fetchResultAfterChanges
                handleVideoAssetChanges(details)
            case .image:
                self.latestPhotoFetchResult = details.fetchResultAfterChanges
                handlePhotoAssetChanges(details)
            default:
                break
            }
        }
    }

    private func handleVideoAssetChanges(_ details: PHFetchResultChangeDetails<PHAsset>) {
        let addedObjects = details.insertedObjects
        let removedObjects = details.removedObjects
        
        if !addedObjects.isEmpty {
            let source: AssetEventSource = isProcessingUserCapture ? .userCapture : .externalChange
            videoAssetEventSubject.send(.added(addedObjects, source: source))
        }
        
        if !removedObjects.isEmpty {
            videoAssetEventSubject.send(.deleted(removedObjects, source: .externalChange))
        }
    }

    private func handlePhotoAssetChanges(_ details: PHFetchResultChangeDetails<PHAsset>) {
        let addedObjects = details.insertedObjects
        let removedObjects = details.removedObjects
        
        if !addedObjects.isEmpty {
            let source: AssetEventSource = isProcessingUserCapture ? .userCapture : .externalChange
            photoAssetEventSubject.send(.added(addedObjects, source: source))
        }
        
        if !removedObjects.isEmpty {
            photoAssetEventSubject.send(.deleted(removedObjects, source: .externalChange))
        }
    }
}
