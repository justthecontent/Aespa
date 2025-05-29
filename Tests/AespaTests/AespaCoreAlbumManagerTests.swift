import XCTest
import Photos
import Combine
@testable import Aespa

#if os(iOS)
typealias TestAsset = MockPHAsset
typealias TestFetchResult = MockPHFetchResult<PHAsset>
@available(iOS 14.0, *)
final class AespaCoreAlbumManagerTests: XCTestCase {
    var sut: AespaCoreAlbumManager!
    var mockPhotoLibrary: MockPHPhotoLibrary!
    var mockCachingProxy: MockAssetCachingProxy!
    var videoEventSubject: AssetEventSubject!
    var photoEventSubject: AssetEventSubject!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockPhotoLibrary = MockPHPhotoLibrary()
        mockCachingProxy = MockAssetCachingProxy()
        videoEventSubject = PassthroughSubject<AssetEvent, Never>()
        photoEventSubject = PassthroughSubject<AssetEvent, Never>()
        cancellables = []
        
        sut = AespaCoreAlbumManager(
            albumName: "TestAlbum",
            mockCachingProxy,
            mockPhotoLibrary,
            videoEventSubject,
            photoEventSubject
        )
    }
    
    override func tearDown() {
        sut = nil
        mockPhotoLibrary = nil
        mockCachingProxy = nil
        videoEventSubject = nil
        photoEventSubject = nil
        cancellables = nil
        super.tearDown()
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .restricted else {
            throw XCTSkip("Photo library access is restricted")
        }
        
        mockPhotoLibrary = MockPHPhotoLibrary()
        mockCachingProxy = MockAssetCachingProxy()
        videoEventSubject = PassthroughSubject<AssetEvent, Never>()
        photoEventSubject = PassthroughSubject<AssetEvent, Never>()
        cancellables = []
        
        sut = AespaCoreAlbumManager(
            albumName: "TestAlbum",
            mockCachingProxy,
            mockPhotoLibrary,
            videoEventSubject,
            photoEventSubject
        )
    }

    func testInitialLoadEvents() async throws {
        // Given
        let expectation = expectation(description: "Initial load events received")
        var receivedEvents: [AssetEvent] = []
        
        videoEventSubject
            .sink { event in
                receivedEvents.append(event)
                if receivedEvents.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Create mock assets
        let mockAsset = MockPHAsset.mockVideo(localIdentifier: "test-video-1")
        let mockAssets = [mockAsset]
        mockPhotoLibrary.mockFetchResult = MockPHFetchResult(assets: mockAssets)
        mockPhotoLibrary.mockAssets = mockAssets
        
        // When
        try await sut.run(loader: AssetLoader(limit: 0, assetType: .video))
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        
        if case .added(_, let source) = receivedEvents.first {
            XCTAssertEqual(source, .initialLoad, "Initial load events should be marked with .initialLoad source")
        } else {
            XCTFail("Expected .added event with .initialLoad source")
        }
    }
    
    func testUserCaptureEvents() async throws {
        // Given
        let expectation = expectation(description: "User capture events received")
        var receivedEvents: [AssetEvent] = []
        
        photoEventSubject
            .sink { event in
                receivedEvents.append(event)
                if receivedEvents.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        let imageData = Data() // Empty data for testing
        try await sut.addToAlbum(imageData: imageData)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        
        if case .added(_, let source) = receivedEvents.first {
            XCTAssertEqual(source, .userCapture, "User capture events should be marked with .userCapture source")
        } else {
            XCTFail("Expected .added event with .userCapture source")
        }
    }
    
    func testExternalChangeEvents() async throws {
        // Given
        let expectation = expectation(description: "External change events received")
        var receivedEvents: [AssetEvent] = []
        
        videoEventSubject
            .sink { event in
                receivedEvents.append(event)
                if receivedEvents.count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Setup initial state
        try await sut.run(loader: AssetLoader(limit: 0, assetType: .video))
        
        // When - Simulate external change
        let insertedAsset = MockPHAsset.mockVideo(localIdentifier: "test-video-external")
        let fetchResult = MockPHFetchResult(assets: [insertedAsset])
        let mockChangeDetails = MockPHFetchResultChangeDetails(
            insertedObjects: [insertedAsset],
            fetchResultAfterChanges: fetchResult
        )
        sut.photoLibraryDidChange(MockPHChange(mockDetails: mockChangeDetails))
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        
        if case .added(_, let source) = receivedEvents.last {
            XCTAssertEqual(source, .externalChange, "External change events should be marked with .externalChange source")
        } else {
            XCTFail("Expected .added event with .externalChange source")
        }
    }
    
    func testEventFiltering() {
        // Given
        let expectation = expectation(description: "Filtered events received")
        expectation.expectedFulfillmentCount = 2 // Expect only user capture and external change events
        var receivedEvents: [AssetEvent] = []
        
        // When
        photoEventSubject
            .filter { event in
                if case .added(_, let source) = event {
                    return source != .initialLoad
                }
                return true
            }
            .sink { event in
                receivedEvents.append(event)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate different types of events
        let mockImageAssets = [
            MockPHAsset.mockImage(localIdentifier: "test-image-1"),
            MockPHAsset.mockImage(localIdentifier: "test-image-2"),
            MockPHAsset.mockImage(localIdentifier: "test-image-3")
        ]
        photoEventSubject.send(.added(mockImageAssets, source: .initialLoad))
        photoEventSubject.send(.added(mockImageAssets, source: .userCapture))
        photoEventSubject.send(.added(mockImageAssets, source: .externalChange))
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvents.count, 2, "Should receive only non-initial load events")
        
        for event in receivedEvents {
            if case .added(_, let source) = event {
                XCTAssertNotEqual(source, .initialLoad, "Should not receive initial load events")
            }
        }
    }
}

// MARK: - Mock Objects

@available(iOS 14.0, *)
final class MockPHPhotoLibrary: PHPhotoLibrary {
    var mockFetchResult: MockPHFetchResult<PHAsset>?
    var mockAssets: [PHAsset] = []
    private var changeObservers: [PHPhotoLibraryChangeObserver] = []
    
    override func register(_ observer: PHPhotoLibraryChangeObserver) {
        changeObservers.append(observer)
    }
    
    override func unregisterChangeObserver(_ observer: PHPhotoLibraryChangeObserver) {
        changeObservers.removeAll { $0 === observer }
    }
    
    override class func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        return .authorized
    }
    
    override class func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        return .authorized
    }
    
    func notifyObservers(with change: PHChange) {
        changeObservers.forEach { $0.photoLibraryDidChange(change) }
    }
}

@available(iOS 14.0, *)
final class MockAssetCachingProxy: AssetCachingProxy {
    var photoAssets: [PhotoAsset] = []
    var videoAssets: [VideoAsset] = []
    
    override func fetchPhoto(_ assets: [PHAsset]) async -> [PhotoAsset] {
        return photoAssets
    }
    
    override func fetchVideo(_ assets: [PHAsset]) async -> [VideoAsset] {
        return videoAssets
    }
    
    func setMockPhotoAssets(_ assets: [PhotoAsset]) {
        photoAssets = assets
    }
    
    func setMockVideoAssets(_ assets: [VideoAsset]) {
        videoAssets = assets
    }
}

@available(iOS 14.0, *)
final class MockPHFetchResultChangeDetails: PHFetchResultChangeDetails<PHAsset> {
    private(set) var insertedObjects: [PHAsset]
    private(set) var removedObjects: [PHAsset]
    private(set) var changedObjects: [PHAsset]
    private(set) var movedObjects: [(from: Int, to: Int)]
    private let mockFetchResultAfterChanges: PHFetchResult<PHAsset>
    
    init(insertedObjects: [PHAsset] = [], 
         removedObjects: [PHAsset] = [], 
         changedObjects: [PHAsset] = [],
         movedObjects: [(from: Int, to: Int)] = [],
         fetchResultAfterChanges: PHFetchResult<PHAsset> = MockPHFetchResult(assets: [])) {
        self.insertedObjects = insertedObjects
        self.removedObjects = removedObjects
        self.changedObjects = changedObjects
        self.movedObjects = movedObjects
        self.mockFetchResultAfterChanges = fetchResultAfterChanges
        super.init()
    }
    
    override var fetchResultAfterChanges: PHFetchResult<PHAsset> {
        return mockFetchResultAfterChanges
    }
    
    override var hasIncrementalChanges: Bool {
        return !insertedObjects.isEmpty || !removedObjects.isEmpty || !changedObjects.isEmpty || !movedObjects.isEmpty
    }
}

@available(iOS 14.0, *)
final class MockPHChange: PHChange {
    let mockDetails: PHFetchResultChangeDetails<PHAsset>
    
    init(mockDetails: PHFetchResultChangeDetails<PHAsset>) {
        self.mockDetails = mockDetails
        super.init()
    }
    
    override func changeDetails(for fetchResult: PHFetchResult<PHAsset>) -> PHFetchResultChangeDetails<PHAsset>? {
        return mockDetails
    }
}

#endif // os(iOS)
