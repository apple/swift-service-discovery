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

import Atomics
import Dispatch

// MARK: - Service discovery protocol

/// Provides service instances lookup.
///
/// ### Threading
///
/// `ServiceDiscovery` implementations **MUST be thread-safe**.
@preconcurrency public protocol ServiceDiscovery: AnyObject, Sendable {
    /// Service identity type
    associatedtype Service: Hashable & Sendable
    /// Service instance type
    associatedtype Instance: Hashable & Sendable

    /// Default timeout for lookup.
    var defaultLookupTimeout: DispatchTimeInterval { get }

    /// Performs a lookup for the given service's instances. The result will be sent to `callback`.
    ///
    /// ``defaultLookupTimeout`` will be used to compute `deadline` in case one is not specified.
    ///
    /// ### Threading
    ///
    /// `callback` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///   - deadline: Lookup is considered to have timed out if it does not complete by this time
    ///   - callback: The closure to receive lookup result
    @preconcurrency func lookup(
        _ service: Service,
        deadline: DispatchTime?,
        callback: @Sendable @escaping (Result<[Instance], Error>) -> Void
    )

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent to `nextResultHandler` when this method is first called. Subsequently,
    /// `nextResultHandler` will only be invoked when the `service`'s instances change.
    ///
    /// ### Threading
    ///
    /// `nextResultHandler` and `completionHandler` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///   - nextResultHandler: The closure to receive update result
    ///   - completionHandler: The closure to invoke when the subscription completes (e.g., when the `ServiceDiscovery` instance exits, etc.),
    ///                 including cancellation requested through `CancellationToken`.
    ///
    /// -  Returns: A ``CancellationToken`` instance that can be used to cancel the subscription in the future.
    @preconcurrency func subscribe(
        to service: Service,
        onNext nextResultHandler: @Sendable @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void
    ) -> CancellationToken
}

// MARK: - Subscription

/// Enables cancellation of service discovery subscription.
public final class CancellationToken: Sendable {
    private let _isCancelled: ManagedAtomic<Bool>
    private let _completionHandler: @Sendable (CompletionReason) -> Void

    /// Returns `true` if the subscription has been cancelled.
    public var isCancelled: Bool { self._isCancelled.load(ordering: .acquiring) }

    /// Creates a new token.
    @preconcurrency public init(
        isCancelled: Bool = false,
        completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) {
        self._isCancelled = ManagedAtomic<Bool>(isCancelled)
        self._completionHandler = completionHandler
    }

    /// Cancels the subscription.
    public func cancel() {
        guard self._isCancelled.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged else {
            return
        }
        self._completionHandler(.cancellationRequested)
    }
}

/// Reason that leads to service discovery subscription completion.
public struct CompletionReason: Equatable, CustomStringConvertible, Sendable {
    internal enum ReasonType: Int, Equatable, CustomStringConvertible {
        case cancellationRequested
        case serviceDiscoveryUnavailable
        case failedToMapService

        var description: String {
            switch self {
            case .cancellationRequested: return "cancellationRequested"
            case .serviceDiscoveryUnavailable: return "serviceDiscoveryUnavailable"
            case .failedToMapService: return "failedToMapService"
            }
        }
    }

    internal let type: ReasonType

    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    public var description: String { "CompletionReason.\(String(describing: self.type))" }

    /// Cancellation requested through `CancellationToken`.
    public static let cancellationRequested = CompletionReason(type: .cancellationRequested)

    /// Service discovery is unavailable.
    public static let serviceDiscoveryUnavailable = CompletionReason(type: .serviceDiscoveryUnavailable)

    /// A service mapping function threw an error
    public static let failedToMapService = CompletionReason(type: .failedToMapService)
}

// MARK: - Service discovery errors

/// Errors that might occur during lookup.
public struct LookupError: Error, Equatable, CustomStringConvertible {
    internal enum ErrorType: Equatable, CustomStringConvertible {
        case unknownService
        case timedOut

        var description: String {
            switch self {
            case .unknownService: return "unknownService"
            case .timedOut: return "timedOut"
            }
        }
    }

    internal let type: ErrorType

    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    public var description: String { "LookupError.\(String(describing: self.type))" }

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
            case .unavailable: return "unavailable"
            case .other(let detail): return "other: \(detail)"
            }
        }
    }

    internal let type: ErrorType

    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    public var description: String { "ServiceDiscoveryError.\(String(describing: self.type))" }

    /// `ServiceDiscovery` instance is unavailable.
    public static let unavailable = ServiceDiscoveryError(type: .unavailable)

    /// Any other error.
    /// - Parameter detail: The error description.
    /// - Returns: A new error.
    public static func other(_ detail: String) -> ServiceDiscoveryError { ServiceDiscoveryError(type: .other(detail)) }
}
