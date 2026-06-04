//
//  ImageProcessingService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-16.
//

import Foundation
import AppKit
import CoreImage
import CoreGraphics
import Vision
import PDFKit
import UniformTypeIdentifiers
import ImageIO

struct ImageConversionFormat: Hashable {
    let displayName: String
    let utType: UTType
    let fileExtension: String
    let supportsCompressionQuality: Bool
}

/// Options for image conversion
struct ImageConversionOptions {
    let format: ImageConversionFormat
    let compressionQuality: Double // 0.0 to 1.0, only applies to JPEG/HEIC
    let maxDimension: CGFloat? // Max width or height, nil for no scaling
    let preserveMetadata: Bool
}

/// Service for processing images (background removal, conversion, PDF creation)
@MainActor
final class ImageProcessingService {
    static let shared = ImageProcessingService()

    private static let preferredFormats: [ImageConversionFormat] = [
        .init(displayName: "PNG", utType: .png, fileExtension: "png", supportsCompressionQuality: false),
        .init(displayName: "JPEG", utType: .jpeg, fileExtension: "jpg", supportsCompressionQuality: true),
        .init(displayName: "WEBP", utType: UTType("org.webmproject.webp") ?? UTType(importedAs: "org.webmproject.webp"), fileExtension: "webp", supportsCompressionQuality: true),
        .init(displayName: "HEIC", utType: .heic, fileExtension: "heic", supportsCompressionQuality: true),
        .init(displayName: "TIFF", utType: .tiff, fileExtension: "tiff", supportsCompressionQuality: false),
        .init(displayName: "BMP", utType: .bmp, fileExtension: "bmp", supportsCompressionQuality: false),
    ]
    
    private init() {}
    private let ciContext = CIContext(options: nil)
    
    // MARK: - Remove Background
    
    /// Removes the background from an image using Vision framework
    func removeBackground(from url: URL) async throws -> URL? {
        guard let inputImage = NSImage(contentsOf: url) else {
            throw ImageProcessingError.invalidImage
        }
        
        guard let cgImage = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }
        
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw ImageProcessingError.backgroundRemovalFailed
        }
        
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        
        let output = try await applyMask(mask, to: cgImage)
        
        let processedImage = NSImage(cgImage: output, size: inputImage.size)
        
        // Create temporary file
        let originalName = url.deletingPathExtension().lastPathComponent
        let newName = "\(originalName)_no_bg.png"
        
        guard let pngData = processedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: pngData),
              let finalData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageProcessingError.saveFailed
        }
        
        guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
            for: .data(finalData, suggestedName: newName)
        ) else {
            throw ImageProcessingError.saveFailed
        }
        
        return tempURL
    }
    
    private func applyMask(_ mask: CVPixelBuffer, to image: CGImage) async throws -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let maskImage = CIImage(cvPixelBuffer: mask)
        
        let filter = CIFilter.blendWithMask()
        filter.inputImage = ciImage
        filter.maskImage = maskImage
        filter.backgroundImage = CIImage.empty()
        
        guard let output = filter.outputImage else {
            throw ImageProcessingError.backgroundRemovalFailed
        }
        
        let context = CIContext()
        guard let result = context.createCGImage(output, from: output.extent) else {
            throw ImageProcessingError.backgroundRemovalFailed
        }
        
        return result
    }
    
    // MARK: - Convert Image

    func availableConversionFormats(for url: URL? = nil) -> [ImageConversionFormat] {
        let writableTypeIdentifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        let sourceTypeIdentifier = url.flatMap {
            try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
        }

        return Self.preferredFormats.filter { format in
            writableTypeIdentifiers.contains(format.utType.identifier) && format.utType.conforms(to: .image)
        }.filter { format in
            guard let sourceTypeIdentifier else { return true }
            return format.utType.identifier != sourceTypeIdentifier
        }
    }
    
    /// Converts an image with specified options
    func convertImage(from url: URL, options: ImageConversionOptions) async throws -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessingError.invalidImage
        }

        var inputImage = NSImage(cgImage: sourceImage, size: .zero)

        // Scale image if needed
        if let maxDim = options.maxDimension {
            inputImage = scaleImage(inputImage, maxDimension: maxDim)
        }

        guard let outputImage = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageProcessingError.invalidImage
        }

        let imageData = try convertToFormat(
            outputImage,
            source: options.preserveMetadata ? source : nil,
            format: options.format,
            quality: options.compressionQuality
        )

        // Create temporary file
        let originalName = url.deletingPathExtension().lastPathComponent
        let newName = "\(originalName)_converted.\(options.format.fileExtension)"
        
        guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
            for: .data(imageData, suggestedName: newName)
        ) else {
            throw ImageProcessingError.saveFailed
        }
        
        return tempURL
    }
    
    private func convertToFormat(
        _ image: CGImage,
        source: CGImageSource?,
        format: ImageConversionFormat,
        quality: Double
    ) throws -> Data {
        let outputData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessingError.conversionFailed
        }

        var properties = (source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }) ?? [:]
        if format.supportsCompressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = quality
        } else {
            properties.removeValue(forKey: kCGImageDestinationLossyCompressionQuality as String)
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessingError.conversionFailed
        }

        return outputData as Data
    }
    
    private func scaleImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        guard maxDimension > 0 else { return image }

        guard let srcCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let srcMax = max(srcCG.width, srcCG.height)
        if CGFloat(srcMax) <= maxDimension {
            return image // no downscaling needed
        }

        let scale = maxDimension / CGFloat(srcMax)

        let ciImage = CIImage(cgImage: srcCG)
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = ciImage
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1.0

        guard let output = lanczos.outputImage else {
            return image
        }

        // Preserve the source color space for exact color matching
        let colorSpace = srcCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let ciContext = CIContext(options: [.workingColorSpace: colorSpace])

        // Render using the CIContext with matching color space
        guard let dstCG = ciContext.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: colorSpace) else {
            return image
        }

        return NSImage(cgImage: dstCG, size: NSSize(width: dstCG.width, height: dstCG.height))
    }
    
    // MARK: - Create PDF
    
    /// Creates a PDF from multiple image URLs
    func createPDF(from imageURLs: [URL], outputName: String? = nil) async throws -> URL? {
        guard !imageURLs.isEmpty else {
            throw ImageProcessingError.noImagesProvided
        }
        
        let pdfDocument = PDFDocument()
        
        for (index, url) in imageURLs.enumerated() {
            guard let image = NSImage(contentsOf: url) else {
                continue
            }
            
            let pdfPage = PDFPage(image: image)
            if let page = pdfPage {
                pdfDocument.insert(page, at: index)
            }
        }
        
        guard pdfDocument.pageCount > 0 else {
            throw ImageProcessingError.pdfCreationFailed
        }
        
        // Create temporary file
        let name = outputName ?? "images_\(Date().timeIntervalSince1970).pdf"
        let pdfName = name.hasSuffix(".pdf") ? name : "\(name).pdf"
        
        guard let pdfData = pdfDocument.dataRepresentation() else {
            throw ImageProcessingError.pdfCreationFailed
        }
        
        guard let tempURL = await TemporaryFileStorageService.shared.createTempFile(
            for: .data(pdfData, suggestedName: pdfName)
        ) else {
            throw ImageProcessingError.saveFailed
        }
        
        return tempURL
    }
    
    // MARK: - Helper Methods
    
    /// Checks if a URL is an image file
    func isImageFile(_ url: URL) -> Bool {
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return contentType.conforms(to: .image)
    }
}

// MARK: - Errors

enum ImageProcessingError: LocalizedError {
    case invalidImage
    case backgroundRemovalFailed
    case conversionFailed
    case pdfCreationFailed
    case noImagesProvided
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The file is not a valid image"
        case .backgroundRemovalFailed:
            return "Failed to remove background from image"
        case .conversionFailed:
            return "Failed to convert image format"
        case .pdfCreationFailed:
            return "Failed to create PDF from images"
        case .noImagesProvided:
            return "No images were provided"
        case .saveFailed:
            return "Failed to save processed file"
        }
    }
}
