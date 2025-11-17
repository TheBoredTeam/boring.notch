//
//  AssociatedObject.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-05.
//

import Foundation
import ObjectiveC


/// Lightweight helper for Objective-C associated objects.
public struct AssociatedObject<Value: AnyObject> {
    private let key: UnsafeRawPointer
    private let policy: objc_AssociationPolicy

    public init(_ policy: objc_AssociationPolicy = .OBJC_ASSOCIATION_RETAIN_NONATOMIC) {
        self.key = UnsafeRawPointer(Unmanaged.passUnretained(UniqueKey()).toOpaque())
        self.policy = policy
    }

    private final class UniqueKey {}

    public subscript<Owner: AnyObject>(_ owner: Owner) -> Value? {
        get { objc_getAssociatedObject(owner, key) as? Value }
        nonmutating set { objc_setAssociatedObject(owner, key, newValue, policy) }
    }
}

extension AssociatedObject: @unchecked Sendable where Value: Sendable {}
