//
//  MosaicServiceHandler.swift
//  MZBar
//
//  Created by Francois on 01/11/2024.
//
import Foundation
import SwiftUI



@objc(MosaicServiceHandler)
class MosaicServiceHandler: NSObject {
    @objc func generateMosaic(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = pboard.pasteboardItems else { return }
        
        let urls = items.compactMap { item -> URL? in
            guard let urlString = item.string(forType: .fileURL) else { return nil }
            return URL(string: urlString)
        }
        
        guard !urls.isEmpty else { return }
        
        DispatchQueue.main.async {
            let viewModel = MosaicViewModel()
            
            viewModel.inputPaths = urls.map { $0.path }
            
            if urls.count == 1 {
                let url = urls[0]
                if url.hasDirectoryPath {
                    viewModel.inputType = .folder
                } else if url.pathExtension.lowercased() == "m3u8" {
                    viewModel.inputType = .m3u8
                } else {
                    viewModel.inputType = .files
                }
            } else {
                viewModel.inputType = .files
            }
            
            viewModel.processInput()
        }
    }
}
