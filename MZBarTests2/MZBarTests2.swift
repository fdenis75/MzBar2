import XCTest
@testable import MZBar
import AVFoundation
class MosaicGeneratorPerformanceTests: XCTestCase {
    var mosaicGenerator: MosaicGenerator!
    var testVideoURL: URL!

    override func setUp() {
        super.setUp()
        mosaicGenerator = MosaicGenerator(debug: false, renderingMode: .classic, maxConcurrentOperations: 4)
        
        // Set up a test video URL. Replace this with an actual video file path for testing.
        testVideoURL = URL(fileURLWithPath: "/Volumes/Ext-6TB-2/01-Models/KB/A/b/20240507_08_SZ3117_Kristy_Black_Marta_Villalobos_4K.mp4")
    }

    override func tearDown() {
        mosaicGenerator = nil
        testVideoURL = nil
        super.tearDown()
    }

    func testPerformanceOfProcessIndivFile() {
        measure {
            let expectation = XCTestExpectation(description: "Process individual file")
            
            Task {
                do {
                    let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("TestOutput")
                    _ = try await mosaicGenerator.processIndivFile(
                        videoFile: testVideoURL,
                        width: 5000,
                        density: "S",
                        format: "jpg",
                        overwrite: true,
                        preview: false,
                        outputDirectory: outputDirectory,
                        accurate: false
                    )
                    expectation.fulfill()
                } catch {
                    XCTFail("Error processing file: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }
    func testGetFilesToday() {
        let expectation = XCTestExpectation(description: "Get files today")
        Task {
            do {
                let files = try await mosaicGenerator.getVideoFilesCreatedTodayWithPlaylistLocation()
                XCTAssertGreaterThan(files.count, 0)
                expectation.fulfill()
            } catch {
                XCTFail("Error getting files: \(error)")
            }
        }
    }
    
    func testcalculateOptimalMosaicLayoutConfiguration() {
        let expectation = XCTestExpectation(description: "Create layout configuration")
        let AR: CGFloat = 16.0 / 9.0
        let estimatedThumbnailCount = 100
        let mosaicWidth = 5000
        let density = "XS"
 
        _ = mosaicGenerator.calculateOptimalMosaicLayoutC(originalAspectRatio: AR, estimatedThumbnailCount: 100, mosaicWidth: 5120, density: "XS")
                expectation.fulfill()
            
    }
    
    func testCreationOfMosaic() {
        let expectation = XCTestExpectation(description: "Create mosaic")
        Task {
            do{
                let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("TestOutput")
                _ = try await mosaicGenerator.processIndivFile(
                    videoFile: testVideoURL,
                    width: 5000,
                    density: "M",
                    format: "jpg",
                    overwrite: true,
                    preview: false,
                    outputDirectory: outputDirectory,
                    accurate: false
                )
                expectation.fulfill()
               
            } catch {
                XCTFail("Error processing file: \(error)")
            }
        }
    }
        
    
 /*   func testPerformanceOfExtractThumbnailsWithTimestamps() {
        let count = 200
        let batchSize = 50
        
            measure {
                let expectation = XCTestExpectation(description: "Extract thumbnails")
                
                Task {
                    do {
                        let asset = AVURLAsset(url: testVideoURL)
                        _ = try await mosaicGenerator.extractThumbnailsWithTimestamps3(
                            from: testVideoURL,
                            count: 250,
                            asset: asset,
                            thSize: CGSize(width: 1080, height: 720),
                            preview: false,
                            accurate: false,
                            batchSize: batchSize
                        )
                        expectation.fulfill()
                    } catch {
                        XCTFail("Error extracting thumbnails: \(error)")
                    }
                }
    
                wait(for: [expectation], timeout: 30.0)
            }
    
    }

  func testPerformanceOfGenerateOptMosaicImagebatch2() {
        measure {
            let expectation = XCTestExpectation(description: "Generate mosaic image")
            
            Task {
                do {
                    let asset = AVURLAsset(url: testVideoURL)
                    let metadata = try await mosaicGenerator.processVideo(file: testVideoURL, asset: asset)
                    let layout = try await mosaicGenerator.mosaicDesign(metadata: metadata, width: 1920, density: "m")
                    
                    let thumbnails = try await mosaicGenerator.extractThumbnailsWithTimestamps3(
                        from: testVideoURL,
                        count: layout.thumbCount,
                        asset: asset,
                        thSize: layout.thumbnailSize,
                        preview: false,
                        accurate: false
                    )
                    
                    _ = try mosaicGenerator.generateOptMosaicImagebatch2(
                        thumbnailsWithTimestamps: thumbnails,
                        layout: layout,
                        outputSize: CGSize(width: 1920, height: 1080),
                        metadata: metadata
                    )
                    expectation.fulfill()
                } catch {
                    XCTFail("Error generating mosaic image: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }

    func testPerformanceOfCreateSummaryVideo() {
        measure {
            let expectation = XCTestExpectation(description: "Create summary video")
            
            Task {
                do {
                    let returnedFiles = [
                        (video: testVideoURL, preview: testVideoURL),
                        (video: testVideoURL, preview: testVideoURL),
                        (video: testVideoURL, preview: testVideoURL)
                    ]
                    let outputFolder = FileManager.default.temporaryDirectory.appendingPathComponent("TestSummaryOutput")
                    _ = try await mosaicGenerator.createSummaryVideo(from: returnedFiles, outputFolder: outputFolder)
                    expectation.fulfill()
                } catch {
                    XCTFail("Error creating summary video: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 60.0)
        }
    }*/
}

