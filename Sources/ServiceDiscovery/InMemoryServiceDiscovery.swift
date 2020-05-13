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
public struct InMemoryServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

    private var serviceInstances: [Service: [Instance]]

    private var serviceSubscribers: [Service: [(Result<[Instance], Error>) -> Void]] = [:]

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

    // TODO: do we need/want to enforce the timeout/deadline here?
    public func lookup(service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        guard var instances = self.serviceInstances[service] else {
            callback(.failure(LookupError.unknownService))
            return
        }

        if let instancesToExclude = self.instancesToExclude {
            instances.removeAll { instancesToExclude.contains($0) }
        }

        callback(.success(instances))
    }

    public mutating func subscribe(service: Service, handler: @escaping (Result<[Instance], Error>) -> Void) {
        // Call `lookup` once and send result to subscriber
        self.lookup(service: service, callback: handler)
        // Add subscriber to list
        var subscribers = self.serviceSubscribers.removeValue(forKey: service) ?? [(Result<[Instance], Error>) -> Void]()
        subscribers.append(handler)
        self.serviceSubscribers[service] = subscribers
    }

    /// Registers `service` and its `instances`.
    public mutating func register(service: Service, instances: [Instance]) {
        let previousInstances = self.serviceInstances[service]
        self.serviceInstances[service] = instances

        if !self.isShutdown, instances != previousInstances, let subscribers = self.serviceSubscribers[service] {
            // Notify subscribers whenever instances change
            subscribers.forEach { $0(.success(instances)) }
        }
    }

    public func shutdown() {
        self._isShutdown.store(true)
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