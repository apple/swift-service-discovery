//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import CServiceDiscoveryHelpers

// Taken from NIO's `NIOAtomic`

public protocol SDAtomicPrimitive {
    associatedtype AtomicWrapper
    static var sd_atomic_create: (Self) -> UnsafeMutablePointer<AtomicWrapper> { get }
    static var sd_atomic_compare_and_exchange: (UnsafeMutablePointer<AtomicWrapper>, Self, Self) -> Bool { get }
    static var sd_atomic_add: (UnsafeMutablePointer<AtomicWrapper>, Self) -> Self { get }
    static var sd_atomic_sub: (UnsafeMutablePointer<AtomicWrapper>, Self) -> Self { get }
    static var sd_atomic_load: (UnsafeMutablePointer<AtomicWrapper>) -> Self { get }
    static var sd_atomic_store: (UnsafeMutablePointer<AtomicWrapper>, Self) -> Void { get }
}

extension Bool: SDAtomicPrimitive {
    public typealias AtomicWrapper = c_sd_atomic_bool
    public static let sd_atomic_create = c_sd_atomic_bool_create
    public static let sd_atomic_compare_and_exchange = c_sd_atomic_bool_compare_and_exchange
    public static let sd_atomic_add = c_sd_atomic_bool_add
    public static let sd_atomic_sub = c_sd_atomic_bool_sub
    public static let sd_atomic_load = c_sd_atomic_bool_load
    public static let sd_atomic_store = c_sd_atomic_bool_store
}

extension Int: SDAtomicPrimitive {
    public typealias AtomicWrapper = c_sd_atomic_long
    public static let sd_atomic_create = c_sd_atomic_long_create
    public static let sd_atomic_compare_and_exchange = c_sd_atomic_long_compare_and_exchange
    public static let sd_atomic_add = c_sd_atomic_long_add
    public static let sd_atomic_sub = c_sd_atomic_long_sub
    public static let sd_atomic_load = c_sd_atomic_long_load
    public static let sd_atomic_store = c_sd_atomic_long_store
}

public class SDAtomic<T: SDAtomicPrimitive> {
    private let rawPointer: UnsafeMutablePointer<T.AtomicWrapper>

    /// Creates an atomic object with `value`.
    public init(_ value: T) {
        self.rawPointer = T.sd_atomic_create(value)
    }

    deinit {
        self.rawPointer.deinitialize(count: 1)
    }

    /// Atomically compares the value against `expected` and, if they are equal,
    /// replaces the value with `desired`.
    ///
    /// - Returns: `True` if the exchange occurred, or `False` if `expected` did not
    ///     match the current value and so no exchange occurred.
    public func compareAndExchange(expected: T, desired: T) -> Bool {
        T.sd_atomic_compare_and_exchange(self.rawPointer, expected, desired)
    }

    /// Atomically adds `rhs` to this object.
    ///
    /// - Returns: The previous value of this object, before the addition occurred.
    public func add(_ rhs: T) -> T {
        T.sd_atomic_add(self.rawPointer, rhs)
    }

    /// Atomically subtracts `rhs` from this object.
    ///
    /// - Returns: The previous value of this object, before the subtraction occurred.
    public func sub(_ rhs: T) -> T {
        T.sd_atomic_sub(self.rawPointer, rhs)
    }

    /// Atomically loads and returns the value of this object.
    public func load() -> T {
        T.sd_atomic_load(self.rawPointer)
    }

    /// Atomically replaces the value of this object with `value`.
    public func store(_ value: T) {
        T.sd_atomic_store(self.rawPointer, value)
    }
}
