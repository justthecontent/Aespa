import Photos
import Foundation

#if os(iOS)
@available(iOS 14.0, *)
class MockPHAsset: PHAsset {
    private let _localIdentifier: String
    private let _mediaType: PHAssetMediaType
    private let _creationDate: Date?
    private let _modificationDate: Date?
    private let _pixelWidth: Int
    private let _pixelHeight: Int
    private let _duration: TimeInterval
    private let _isFavorite: Bool
    
    init(
        localIdentifier: String = UUID().uuidString,
        mediaType: PHAssetMediaType = .image,
        creationDate: Date? = Date(),
        modificationDate: Date? = Date(),
        pixelWidth: Int = 1920,
        pixelHeight: Int = 1080,
        duration: TimeInterval = 0.0,
        isFavorite: Bool = false
    ) {
        self._localIdentifier = localIdentifier
        self._mediaType = mediaType
        self._creationDate = creationDate
        self._modificationDate = modificationDate
        self._pixelWidth = pixelWidth
        self._pixelHeight = pixelHeight
        self._duration = duration
        self._isFavorite = isFavorite
        super.init()
    }
    
    override var localIdentifier: String {
        return _localIdentifier
    }
    
    override var mediaType: PHAssetMediaType {
        return _mediaType
    }
    
    override var creationDate: Date? {
        return _creationDate
    }
    
    override var modificationDate: Date? {
        return _modificationDate
    }
    
    override var pixelWidth: Int {
        return _pixelWidth
    }
    
    override var pixelHeight: Int {
        return _pixelHeight
    }
    
    override var duration: TimeInterval {
        return _duration
    }
    
    override var isFavorite: Bool {
        return _isFavorite
    }
    
    static func mockImage(
        localIdentifier: String = UUID().uuidString,
        creationDate: Date = Date()
    ) -> MockPHAsset {
        return MockPHAsset(
            localIdentifier: localIdentifier,
            mediaType: .image,
            creationDate: creationDate
        )
    }
    
    static func mockVideo(
        localIdentifier: String = UUID().uuidString,
        creationDate: Date = Date(),
        duration: TimeInterval = 30.0
    ) -> MockPHAsset {
        return MockPHAsset(
            localIdentifier: localIdentifier,
            mediaType: .video,
            creationDate: creationDate,
            duration: duration
        )
    }
}

extension MockPHAsset: Equatable {
    static func == (lhs: MockPHAsset, rhs: MockPHAsset) -> Bool {
        return lhs.localIdentifier == rhs.localIdentifier
    }
}

// MARK: - Mock PHFetchResult for MockPHAsset
@available(iOS 14.0, *)
class MockPHFetchResult<T>: PHFetchResult<T> {
    private let mockAssets: [T]
    
    init(assets: [T]) {
        self.mockAssets = assets
        super.init()
    }
    
    override var count: Int {
        return mockAssets.count
    }
    
    override func object(at index: Int) -> T {
        return mockAssets[index]
    }
    
    override func objects(at indexes: IndexSet) -> [T] {
        return indexes.map { mockAssets[$0] }
    }
    
    override func contains(_ anObject: T) -> Bool where T : AnyObject {
        return mockAssets.contains { $0 === anObject }
    }
    
    override func index(of asset: T) -> Int where T : AnyObject {
        return mockAssets.firstIndex { $0 === asset } ?? NSNotFound
    }
    
    override func firstObject -> T? {
        return mockAssets.first
    }
    
    override func lastObject -> T? {
        return mockAssets.last
    }
}
#endif // os(iOS)

