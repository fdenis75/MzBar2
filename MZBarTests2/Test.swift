//
//  Test.swift
//  MZBarTests2
//
//  Created by Francois on 29/10/2024.
//

import Testing
@testable import MZBar
import AVFoundation


struct TestMZbar {
    var mosaicGenerator: MosaicGenerator!
    var testVideoURL: String
    init()  {
        mosaicGenerator = MosaicGenerator(debug: false, renderingMode: .classic, maxConcurrentOperations: 4, custom: false)
        testVideoURL = "/Volumes/Ext-6TB-2/01-Models/Chrissy Curves/LP/NR384_Natalee_1080P.mp4"
    }
    
    @Test func createPreview() async throws {
        try await mosaicGenerator.getFiles(input: testVideoURL, width: 5000)
        
        for density in ([ "XXL"]) {
            print("starting test \(density)")
            let result = try await mosaicGenerator.RunGen(input: testVideoURL, width: 5000, density: density, format: "heic", preview: true)
                #expect(result != nil)
        }
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
