//
//  AssociatedObject.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-05.
//

import Foundation
import ObjectiveC

private nonisolated final class AssociatedObjectKey: @unchecked Sendable {}

/// Lightweight helper for Objective-C associated objects.
public struct AssociatedObject<Value: AnyObject> {
    // Retain the key object for the lifetime of this wrapper. Keeping only its raw
    // pointer lets ARC immediately free it and can cause address reuse collisions.
    private let keyOwner: AssociatedObjectKey
    private let key: UnsafeRawPointer
    private let policy: objc_AssociationPolicy

    public init(_ policy: objc_AssociationPolicy = .OBJC_ASSOCIATION_RETAIN_NONATOMIC) {
        let keyOwner = AssociatedObjectKey()
        self.keyOwner = keyOwner
        self.key = UnsafeRawPointer(Unmanaged.passUnretained(keyOwner).toOpaque())
        self.policy = policy
    }

    public subscript<Owner: AnyObject>(_ owner: Owner) -> Value? {
        get { objc_getAssociatedObject(owner, key) as? Value }
        nonmutating set { objc_setAssociatedObject(owner, key, newValue, policy) }
    }
}

extension AssociatedObject: @unchecked Sendable where Value: Sendable {}
