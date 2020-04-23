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

    /// Indicates if `shutdown` has been issued and therefore all subscriptions are cancelled.
    var isShutdown: Bool { get }

    /// Performs a lookup for the `service`'s instances. The result will be sent to `callback`.
    func lookup(service: Service, deadline: DispatchTime?, callback: @escaping (Result<Set<Instance>, Error>) -> Void)

    /// Performs clean up steps if any before shutting down.
    func shutdown() throws
}

/// Represents errors that might occur during lookup.
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

// MARK: - Dynamic service discovery protocol

/// Provides lookup for service instances that might change.
public protocol DynamicServiceDiscovery: ServiceDiscovery, AnyObject {
    /// Default refresh interval for `subscribe`.
    var defaultRefreshInterval: DispatchTimeInterval { get }

    /// Subscribes to receive `service`'s instances, which gets polled and refreshed automatically at `refreshInterval`.
    /// `handler` will be called after the first lookup completes, and subsequently only when the instances change.
    ///
    /// The configured `defaultRefreshInterval` will be used when `refreshInteral` is  `nil`.
    func subscribe(service: Service, refreshInterval: DispatchTimeInterval?, handler: @escaping (Set<Instance>) -> Void)
}

extension DynamicServiceDiscovery {
    public func subscribe(service: Service, refreshInterval: DispatchTimeInterval? = nil, handler: @escaping (Set<Instance>) -> Void) {
        self.lookup(service: service, deadline: nil) { result in
            switch result {
            case .success(let instances):
                handler(instances)
                self._subscribe(service: service, refreshInterval: refreshInterval, previousInstances: instances, onChange: handler)
            case .failure:
                self._subscribe(service: service, refreshInterval: refreshInterval, previousInstances: nil, onChange: handler)
            }
        }
    }

    private func _subscribe(service: Service, refreshInterval: DispatchTimeInterval?, previousInstances: Set<Instance>?, onChange: @escaping (Set<Instance>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + (refreshInterval ?? self.defaultRefreshInterval)) { [weak self] in
            if let self = self {
                guard !self.isShutdown else { return }

                self.lookup(service: service, deadline: nil) { result in
                    // Subsequent lookups should only notify if instances have changed
                    switch result {
                    case .success(let instances):
                        if previousInstances != instances {
                            onChange(instances)
                        }
                        self._subscribe(service: service, refreshInterval: refreshInterval, previousInstances: instances, onChange: onChange)
                    case .failure:
                        self._subscribe(service: service, refreshInterval: refreshInterval, previousInstances: previousInstances, onChange: onChange)
                    }
                }
            }
        }
    }
}
