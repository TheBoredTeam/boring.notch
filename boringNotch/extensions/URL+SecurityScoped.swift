//
//  URL+SecurityScoped.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import AppKit

// MARK: - Error Types

extension URL {
    func accessSecurityScopedResource<Value>(accessor: (URL) throws -> Value) rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer { 
            if didStartAccessing { 
                stopAccessingSecurityScopedResource() 
            }
        }
        return try accessor(self)
    }
    
    /// Async version of accessSecurityScopedResource
    func accessSecurityScopedResource<Value>(accessor: (URL) async throws -> Value) async rethrows -> Value {
        let didStartAccessing = startAccessingSecurityScopedResource()
        defer { 
            if didStartAccessing { 
                stopAccessingSecurityScopedResource() 
            }
        }
        return try await accessor(self)
    }
}

extension [URL] {
    func accessSecurityScopedResources<Value>(accessor: ([URL]) async throws -> Value) async rethrows -> Value {
        let didStart = self.map { $0.startAccessingSecurityScopedResource() }
        
        defer {
            for (url, started) in zip(self, didStart) where started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        return try await accessor(self)
    }
}

