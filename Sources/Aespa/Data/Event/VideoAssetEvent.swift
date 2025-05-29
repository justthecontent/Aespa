//
//  File.swift
//  
//
//  Created by YoungBin Lee on 4/18/24.
//

import Combine
import Photos

public typealias AssetEventSubject = PassthroughSubject<AssetEvent, Never>

/// Indicates the source/origin of an asset event
public enum AssetEventSource {
    /// Event triggered during initial loading of assets at app startup
    case initialLoad
    /// Event triggered by user capturing photo/video in the app
    case userCapture
    /// Event triggered by external changes to the photo library
    case externalChange
}

public enum AssetEvent {
    case added([PHAsset], source: AssetEventSource)
    case deleted([PHAsset], source: AssetEventSource)
}

// Extension to maintain backward compatibility for existing code
public extension AssetEvent {
    var assets: [PHAsset] {
        switch self {
        case .added(let assets, _):
            return assets
        case .deleted(let assets, _):
            return assets
        }
    }
    
    var isAddition: Bool {
        switch self {
        case .added(_, _):
            return true
        case .deleted(_, _):
            return false
        }
    }
}

public extension [VideoAsset] {
    /// If you want to delete your current `VideoAsset` based on a `PHAsset`, use this method.
    /// The `id` of a `VideoAsset` is the `id` of the encapsulated `PHAsset`, and this method operates based on that.
    ///
    /// If your goal is simply to keep `VideoAssets` up to date, consider using the `fetchVideoFiles` of `AespaSession`.
    /// `fetchVideoFiles` utilizes caching internally, allowing for faster and more efficient data updates.
    func remove(_ asset: PHAsset) -> [VideoAsset] {
        filter { $0.phAsset.localIdentifier != asset.localIdentifier }
    }
    
    /// Removes assets that were deleted according to the provided AssetEvent
    func remove(deletedIn event: AssetEvent) -> [VideoAsset] {
        guard case .deleted(let assets, _) = event else { return self }
        return filter { asset in
            !assets.contains { $0.localIdentifier == asset.phAsset.localIdentifier }
        }
    }
}

public extension [PhotoAsset] {
    /// If you want to delete your current `PhotoAsset` based on a `PHAsset`, use this method.
    /// The `id` of a `VideoAsset` is the `id` of the encapsulated `PHAsset`, and this method operates based on that.
    ///
    /// If your goal is simply to keep `PhotoAsset` up to date, consider using the `fetchPhotoFiles` of `AespaSession`.
    /// `fetchPhotoFiles` utilizes caching internally, allowing for faster and more efficient data updates.
    func remove(_ asset: PHAsset) -> [PhotoAsset] {
        filter { $0.asset.localIdentifier != asset.localIdentifier }
    }
    
    /// Removes assets that were deleted according to the provided AssetEvent
    func remove(deletedIn event: AssetEvent) -> [PhotoAsset] {
        guard case .deleted(let assets, _) = event else { return self }
        return filter { asset in
            !assets.contains { $0.localIdentifier == asset.asset.localIdentifier }
        }
    }
}
