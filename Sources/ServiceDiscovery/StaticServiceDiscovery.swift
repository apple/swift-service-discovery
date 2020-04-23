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

/// Provides lookup for service instances that are static and remain unchanged after initialization.
public struct StaticServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

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
        precondition(configuration.instances.count > 0, "At least one service must be registered")

        self.configuration = configuration
    }

    // TODO: do we need/want to enforce the timeout/deadline here?
    public func lookup(service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<Set<Instance>, Error>) -> Void) {
        guard var instances = self.configuration.instances[service] else {
            callback(.failure(LookupError.unknownService))
            return
        }

        if let instancesToExclude = self.instancesToExclude {
            instances.subtract(instancesToExclude)
        }

        callback(.success(instances))
    }

    public func shutdown() {
        self._isShutdown.store(true)
    }
}

extension StaticServiceDiscovery {
    public struct Configuration {
        /// Default configuration
        public static var `default`: Configuration {
            .init()
        }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

        /// Instances to exclude from lookup results.
        public var instancesToExclude: Set<Instance>?

        internal var instances: [Service: Set<Instance>]

        public init() {
            self.init(instances: [:])
        }

        /// Initializes `StaticServiceDiscovery` with the given service to instances mappings.
        public init(instances: [Service: Set<Instance>]) {
            self.instances = instances
        }

        /// Registers a `service` and its `instances`.
        public mutating func register(service: Service, instances: Set<Instance>) {
            self.instances[service] = instances
        }
    }
}
