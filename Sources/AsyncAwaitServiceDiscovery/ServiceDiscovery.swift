//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

#if compiler(>=5.5)
/// Provides service instances lookup.
@available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
public protocol ServiceDiscovery: AnyObject {
    /// Service identity type
    associatedtype Service: Hashable
    /// Service instance type
    associatedtype Instance: Hashable

    /// Default timeout for lookup.
    var defaultLookupTimeout: DispatchTimeInterval { get }

    /// Performs a lookup for the given service's instances.
    ///
    /// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///   - deadline: Lookup is considered to have timed out if it does not complete by this time
    ///
    /// - Returns: The service's instances. An error is thrown in case `service` is unknown.
    func lookup(_ service: Service, deadline: DispatchTime?) async throws -> [Instance]

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent as the first element of the stream. Subsequent elements
    /// are produced only when the `service`'s instances change.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///
    /// -  Returns: A stream of the service's instances as they are updated.
    func subscribe(to service: Service) async throws -> AsyncThrowingStream<[Instance]>
}
#endif

// MARK: - Service discovery errors

/// Errors that might occur during lookup.
public struct LookupError: Error, Equatable, CustomStringConvertible {
    internal enum ErrorType: Equatable, CustomStringConvertible {
        case unknownService
        case timedOut

        var description: String {
            switch self {
            case .unknownService:
                return "unknownService"
            case .timedOut:
                return "timedOut"
            }
        }
    }

    internal let type: ErrorType

    public var description: String {
        "LookupError.\(String(describing: self.type))"
    }

    /// Lookup cannot be completed because the service is unknown.
    public static let unknownService = LookupError(type: .unknownService)

    /// Lookup has taken longer than allowed and thus has timed out.
    public static let timedOut = LookupError(type: .timedOut)
}

/// General service discovery errors.
public struct ServiceDiscoveryError: Error, Equatable, CustomStringConvertible {
    internal enum ErrorType: Equatable, CustomStringConvertible {
        case unavailable

        var description: String {
            switch self {
            case .unavailable:
                return "unavailable"
            }
        }
    }

    internal let type: ErrorType

    public var description: String {
        "ServiceDiscoveryError.\(String(describing: self.type))"
    }

    /// `ServiceDiscovery` instance is unavailable.
    public static let unavailable = ServiceDiscoveryError(type: .unavailable)
}
