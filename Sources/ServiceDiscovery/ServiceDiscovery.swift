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
public protocol ServiceDiscovery {
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
    /// - Parameters:
    ///   - service: The service to lookup
    ///   - deadline: Lookup is considered to have timed out if it does not complete by this time
    ///   - callback: The closure to receive lookup result
    func lookup(_ service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent to `handler` when this method is first invoked. Subsequently,
    /// `handler` will only receive updates when the `service`'s instances change.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///   - onTerminate: The closure to invoke when the subscription terminates
    ///   - handler: The closure to receive update
    ///
    /// -  Returns: A `CancellationToken` instance that can be used to cancel the subscription in the future.
    func subscribe(to service: Service, onTerminate: @escaping () -> Void, handler: @escaping (Result<[Instance], Error>) -> Void) -> CancellationToken
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

// MARK: - Cancellation token for `subscribe`

/// Enables cancellation of service discovery subscription.
public class CancellationToken {
    private let _isCanceled: SDAtomic<Bool>

    /// Returns  `true` if  the subscription has been canceled.
    public var isCanceled: Bool {
        self._isCanceled.load()
    }

    /// Creates a new token.
    public init() {
        self._isCanceled = SDAtomic<Bool>(false)
    }

    /// Cancels the subscription.
    public func cancel() {
        self._isCanceled.store(true)
    }
}
