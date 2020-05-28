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

/// Provides lookup for service instances that are stored in-memory.
public class InMemoryServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

    private var serviceInstances: [Service: [Instance]]

    private var serviceSubscriptions: [Service: [Subscription]] = [:]

    public var defaultLookupTimeout: DispatchTimeInterval {
        self.configuration.defaultLookupTimeout
    }

    public var instancesToExclude: Set<Instance>? {
        self.configuration.instancesToExclude
    }

    private let _isShutdown = SDAtomic<Bool>(false)

    public var isShutdown: Bool {
        self._isShutdown.load()
    }

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.serviceInstances = configuration.serviceInstances
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[Instance], Error>! // !-safe because if-else block always set `result` otherwise the operation has timed out

        DispatchQueue.global().async {
            if var instances = self.serviceInstances[service] {
                if let instancesToExclude = self.instancesToExclude {
                    instances.removeAll { instancesToExclude.contains($0) }
                }
                result = .success(instances)
            } else {
                result = .failure(LookupError.unknownService)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: deadline ?? DispatchTime.now() + self.defaultLookupTimeout) == .timedOut {
            result = .failure(LookupError.timedOut)
        }

        callback(result)
    }

    public func subscribe(to service: Service, onTerminate: @escaping () -> Void, handler: @escaping (Result<[Instance], Error>) -> Void) -> SubscriptionToken {
        // Call `lookup` once and send result to subscriber
        self.lookup(service, callback: handler)

        let token = SubscriptionToken()
        let subscription = Subscription(handler: handler, onTerminate: onTerminate, token: token)

        // Save the subscription
        var subscriptions = self.serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
        subscriptions.append(subscription)
        self.serviceSubscriptions[service] = subscriptions

        return token
    }

    /// Registers a service and its `instances`.
    public func register(_ service: Service, instances: [Instance]) {
        let previousInstances = self.serviceInstances[service]
        self.serviceInstances[service] = instances

        if !self.isShutdown, instances != previousInstances, let subscriptions = self.serviceSubscriptions[service] {
            // Notify subscribers whenever instances change
            subscriptions
                .filter { !$0.token.isCanceled }
                .forEach { $0.handler(.success(instances)) }
        }
    }

    public func shutdown() {
        self._isShutdown.store(true)
        self.serviceSubscriptions.values.forEach { subscriptions in
            subscriptions
                .filter { !$0.token.isCanceled }
                .forEach { $0.onTerminate() }
        }
    }

    private struct Subscription {
        let handler: (Result<[Instance], Error>) -> Void
        let onTerminate: () -> Void
        let token: SubscriptionToken
    }
}

extension InMemoryServiceDiscovery {
    public struct Configuration {
        /// Default configuration
        public static var `default`: Configuration {
            .init()
        }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

        /// Instances to exclude from lookup results
        public var instancesToExclude: Set<Instance>?

        internal var serviceInstances: [Service: [Instance]]

        public init() {
            self.init(serviceInstances: [:])
        }

        /// Initializes `InMemoryServiceDiscovery` with the given service to instances mappings.
        public init(serviceInstances: [Service: [Instance]]) {
            self.serviceInstances = serviceInstances
        }

        /// Registers `service` and its `instances`.
        public mutating func register(service: Service, instances: [Instance]) {
            self.serviceInstances[service] = instances
        }
    }
}
