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

import Dispatch

/// Provides service instances lookup.
public protocol ServiceDiscovery {
    /// Service identity type
    associatedtype Service: Hashable
    /// Service instance type
    associatedtype Instance: Hashable

    /// Default timeout for lookup.
    var defaultLookupTimeout: DispatchTimeInterval { get }

    /// Instances to exclude from lookup results.
    var instancesToExclude: Set<Instance>? { get }

    /// Indicates if `shutdown` has been issued and therefore all subscriptions are cancelled.
    var isShutdown: Bool { get }

    /// Performs a lookup for the given service's instances. The result will be sent to `callback`.
    ///
    /// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
    mutating func lookup(_ service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent to `handler` when this method is first invoked. Subsequently,
    /// `handler` will only receive updates when the `service`'s instances change.
    mutating func subscribe(to service: Service, handler: @escaping (Result<[Instance], Error>) -> Void)

    /// Performs clean up steps if any before shutting down.
    mutating func shutdown() throws
}

/// Errors that might occur during lookup.
public struct LookupError: Error, Equatable, CustomStringConvertible {
    internal enum ErrorType: Equatable, CustomStringConvertible {
        case unknownService
        case timedOut

        public var description: String {
            switch self {
            case .unknownService:
                return "unknownService"
            case .timedOut:
                return "timedOut"
            }
        }
    }

    internal let type: ErrorType

    internal init(type: ErrorType) {
        self.type = type
    }

    public var description: String {
        "LookupError.\(String(describing: self.type))"
    }

    /// Lookup cannot be completed because the service is unknown.
    public static let unknownService = LookupError(type: .unknownService)

    /// Lookup has taken longer than allowed and thus has timed out.
    public static let timedOut = LookupError(type: .timedOut)
}
