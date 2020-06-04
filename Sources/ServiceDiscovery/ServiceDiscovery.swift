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
import ServiceDiscoveryHelpers

// MARK: - Service discovery protocol

/// Provides service instances lookup.
///
/// ### Threading
///
/// `ServiceDiscovery` implementations **MUST be thread-safe**.
public protocol ServiceDiscovery: AnyObject {
    /// Service identity type
    associatedtype Service: Hashable
    /// Service instance type
    associatedtype Instance: Hashable

    /// Default timeout for lookup.
    var defaultLookupTimeout: DispatchTimeInterval { get }

    /// Instances to exclude from lookup results.
    var instancesToExclude: Set<Instance>? { get }

    /// Performs a lookup for the given service's instances. The result will be sent to `callback`.
    ///
    /// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
    ///
    /// ### Threading
    ///
    /// `callback` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///   - deadline: Lookup is considered to have timed out if it does not complete by this time
    ///   - callback: The closure to receive lookup result
    func lookup(_ service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent to `onNext` when this method is first called. Subsequently,
    /// `onNext` will only be invoked when the `service`'s instances change.
    ///
    /// ### Threading
    ///
    /// `onNext` and `onComplete` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///   - onNext: The closure to receive update result
    ///   - onComplete: The closure to invoke when the subscription completes (e.g., when the `ServiceDiscovery` instance exits, etc.),
    ///                 including cancellation requested through `CancellationToken`.
    ///
    /// -  Returns: A `CancellationToken` instance that can be used to cancel the subscription in the future.
    func subscribe(to service: Service, onNext: @escaping (Result<[Instance], Error>) -> Void, onComplete: @escaping (CompletionReason) -> Void) -> CancellationToken
}

// MARK: - Subscription

/// Enables cancellation of service discovery subscription.
public class CancellationToken {
    private let _isCancelled: SDAtomic<Bool>
    private let _completionHandler: (CompletionReason) -> Void

    /// Returns `true` if the subscription has been cancelled.
    public var isCancelled: Bool {
        self._isCancelled.load()
    }

    /// Creates a new token.
    public init(isCancelled: Bool = false, completionHandler: @escaping (CompletionReason) -> Void = { _ in }) {
        self._isCancelled = SDAtomic<Bool>(isCancelled)
        self._completionHandler = completionHandler
    }

    /// Cancels the subscription.
    public func cancel() {
        guard self._isCancelled.compareAndExchange(expected: false, desired: true) else { return }
        self._completionHandler(.cancellationRequested)
    }
}

/// Reason that leads to service discovery subscription completion.
public struct CompletionReason: Equatable, CustomStringConvertible {
    internal enum ReasonType: Int, Equatable, CustomStringConvertible {
        case cancellationRequested
        case serviceDiscoveryUnavailable

        var description: String {
            switch self {
            case .cancellationRequested:
                return "cancellationRequested"
            case .serviceDiscoveryUnavailable:
                return "serviceDiscoveryUnavailable"
            }
        }
    }

    internal let type: ReasonType

    public var description: String {
        "CompletionReason.\(String(describing: self.type))"
    }

    /// Cancellation requested through `CancellationToken`.
    public static let cancellationRequested = CompletionReason(type: .cancellationRequested)

    /// Service discovery is unavailable.
    public static let serviceDiscoveryUnavailable = CompletionReason(type: .serviceDiscoveryUnavailable)
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
