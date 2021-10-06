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

import Atomics
import Dispatch
import Foundation // for NSLock

/// Provides lookup for service instances that are stored in-memory.
public final class InMemoryServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

    private let serviceInstancesLock = NSLock()
    private var serviceInstances: [Service: [Instance]]

    private let serviceSubscriptionsLock = NSLock()
    private var serviceSubscriptions: [Service: [Subscription]] = [:]

    private let queue: DispatchQueue

    public var defaultLookupTimeout: DispatchTimeInterval {
        self.configuration.defaultLookupTimeout
    }

    private let _isShutdown = ManagedAtomic<Bool>(false)

    public var isShutdown: Bool {
        self._isShutdown.load(ordering: .acquiring)
    }

    public init(configuration: Configuration, queue: DispatchQueue = .init(label: "InMemoryServiceDiscovery", attributes: .concurrent)) {
        self.configuration = configuration
        self.serviceInstances = configuration.serviceInstances
        self.queue = queue
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil) async throws -> [Instance] {
        guard !self.isShutdown else {
            throw ServiceDiscoveryError.unavailable
        }

        let task: Task<[Instance], Error> = Task.detached {
            let instances = self.serviceInstancesLock.withLock {
                self.serviceInstances[service]
            }

            // This task is cancelled at deadline
            guard !Task.isCancelled else {
                throw LookupError.timedOut
            }
            guard let instances = instances else {
                throw LookupError.unknownService
            }
            return instances
        }

        // Timeout handler
        self.queue.asyncAfter(deadline: deadline ?? DispatchTime.now() + self.defaultLookupTimeout) {
            task.cancel()
        }

        return try await task.value
    }

    public func subscribe(to service: Service) throws -> AsyncThrowingStream<[Instance], Error> {
        guard !self.isShutdown else {
            throw ServiceDiscoveryError.unavailable
        }

        return AsyncThrowingStream { continuation in
            Task.detached { () -> Void in
                // Call `lookup` once and send it as the first stream element
                do {
                    let instances = try await self.lookup(service)
                    continuation.yield(instances)
                } catch is LookupError {
                    // LookupError is recoverable (e.g., service is added *after* subscription begins), so don't bail yet
                } catch {
                    return continuation.finish(throwing: error)
                }

                // Create subscription
                let subscription = Subscription(
                    id: UUID(),
                    nextResultHandler: { instances in continuation.yield(instances) },
                    completionHandler: { error in
                        if let error = error {
                            continuation.finish(throwing: error)
                        } else {
                            continuation.finish()
                        }
                    }
                )

                // Save the subscription
                self.serviceSubscriptionsLock.withLock {
                    var subscriptions = self.serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
                    subscriptions.append(subscription)
                    self.serviceSubscriptions[service] = subscriptions
                }

                // Remove the subscription when it terminates
                continuation.onTermination = { @Sendable (_) -> Void in
                    // Don't worry about updating subscriptions on global shutdown
                    guard !self.isShutdown else { return }

                    self.serviceSubscriptionsLock.withLock {
                        var subscriptions = self.serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
                        subscriptions.removeAll { $0.id == subscription.id }
                        self.serviceSubscriptions[service] = subscriptions
                    }
                }
            }
        }
    }

    /// Registers a service and its `instances`.
    public func register(_ service: Service, instances: [Instance]) {
        guard !self.isShutdown else { return }

        var previousInstances: [Instance]?
        self.serviceInstancesLock.withLock {
            previousInstances = self.serviceInstances[service]
            self.serviceInstances[service] = instances
        }

        self.serviceSubscriptionsLock.withLock {
            if !self.isShutdown, instances != previousInstances, let subscriptions = self.serviceSubscriptions[service] {
                // Notify subscribers whenever instances change
                subscriptions.forEach { $0.nextResultHandler(instances) }
            }
        }
    }

    public func shutdown() {
        guard self._isShutdown.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged else { return }

        self.serviceSubscriptionsLock.withLock {
            self.serviceSubscriptions.values.forEach { subscriptions in
                subscriptions.forEach { $0.completionHandler(ServiceDiscoveryError.unavailable) }
            }
        }
    }

    private struct Subscription {
        let id: UUID
        let nextResultHandler: ([Instance]) -> Void
        let completionHandler: (Error?) -> Void
    }
}

public extension InMemoryServiceDiscovery {
    struct Configuration {
        /// Default configuration
        public static var `default`: Configuration {
            .init()
        }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

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

// MARK: - NSLock extensions

private extension NSLock {
    func withLock<Value>(_ body: () -> Value) -> Value {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}
