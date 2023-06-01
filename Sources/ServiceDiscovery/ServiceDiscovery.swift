//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// MARK: - Service discovery protocol

/// Provides service instances lookup.
///
/// ### Threading
///
/// `ServiceDiscovery` implementations **MUST be thread-safe**.
public protocol ServiceDiscovery {
    /// Service identity type
    associatedtype Service
    /// Service instance type
    associatedtype Instance

    /// Performs async lookup for the given service's instances.
    ///
    /// ``defaultLookupTimeout`` will be used to compute `deadline` in case one is not specified.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///
    /// -  Returns: A listing of service instances.
    func lookup(_ service: Service, deadline: ContinuousClock.Instant?) async throws -> [Instance]

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// Returns a ``ServiceDiscoveryInstanceSequence``, which is an `AsyncSequence` and each of its items is a snapshot listing of service instances.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///
    /// -  Returns: A ``ServiceDiscoveryInstanceSequence`` async sequence.
    func subscribe(_ service: Service) async throws -> any ServiceDiscoveryInstanceSequence<Instance>
}

public protocol ServiceDiscoveryInstanceSequence<Instance>: AsyncSequence where Self.Element == Instance {
    associatedtype Instance
}

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
        case other(String)

        var description: String {
            switch self {
            case .unavailable:
                return "unavailable"
            case .other(let detail):
                return "other: \(detail)"
            }
        }
    }

    internal let type: ErrorType

    public var description: String {
        "ServiceDiscoveryError.\(String(describing: self.type))"
    }

    /// `ServiceDiscovery` instance is unavailable.
    public static let unavailable = ServiceDiscoveryError(type: .unavailable)

    public static func other(_ detail: String) -> ServiceDiscoveryError {
        ServiceDiscoveryError(type: .other(detail))
    }
}
