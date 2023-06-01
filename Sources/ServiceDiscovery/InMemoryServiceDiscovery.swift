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

public actor InMemoryServiceDiscovery<Service: Hashable, Instance>: ServiceDiscovery {
    private let configuration: Configuration

    private var instances: [Service: [Instance]]
    private var subscriptions: [Service: Set<Subscription>]

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.instances = configuration.instances
        self.subscriptions = [:]
    }

    public func lookup(_ service: Service, deadline: ContinuousClock.Instant?) async throws -> [Instance] {
        if let instances = self.instances[service] {
            return instances
        } else {
            throw LookupError.unknownService
        }
    }

    public func subscribe(_ service: Service) async throws -> any ServiceDiscoveryInstanceSequence<Instance> {
        let (subscription, sequence) = Subscription.makeSubscription(terminationHandler: { subscription in
            Task {
                await self.unsubscribe(service: service, subscription: subscription)
            }
        })

        // reduce CoW
        var subscriptions = self.subscriptions.removeValue(forKey: service) ?? []
        subscriptions.insert(subscription)
        self.subscriptions[service] = subscriptions

        do {
            let instances = try await self.lookup(service, deadline: nil)
            subscription.yield(instances)
        } catch {
            // FIXME: nicer try/catch syntax?
            if let lookupError = error as? LookupError, lookupError == LookupError.unknownService {
                subscription.yield([])
            } else {
                subscription.yield(error)
            }
        }

        return sequence
    }

    private func unsubscribe(service: Service, subscription: Subscription) {
        guard var subscriptions = self.subscriptions.removeValue(forKey: service) else {
            return
        }
        subscriptions.remove(subscription)
        if !subscriptions.isEmpty {
            self.subscriptions[service] = subscriptions
        }
    }

    /// Registers `service` and its `instances`.
    public func register(service: Service, instances: [Instance]) async {
        self.instances[service] = instances

        if let subscriptions = self.subscriptions[service] {
            for subscription in subscriptions {
                subscription.yield(instances)
            }
        }
    }

    private class Subscription: Identifiable, Hashable {
        private let continuation: AsyncThrowingStream<Instance, Error>.Continuation

        static func makeSubscription(terminationHandler: @Sendable @escaping (Subscription) -> Void) -> (Subscription, InstanceSequence) {
            #if swift(<5.9)
            var continuation: AsyncThrowingStream<Instance, Error>.Continuation!
            let stream = AsyncThrowingStream { _continuation in
                continuation = _continuation
            }
            #else
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Instance.self)
            #endif
            let subscription = Subscription(continuation)
            continuation.onTermination = { @Sendable _ in terminationHandler(subscription) }
            return (subscription, InstanceSequence(stream))
        }

        private init(_ continuation: AsyncThrowingStream<Instance, Error>.Continuation) {
            self.continuation = continuation
        }

        func yield(_ instances: [Instance]) {
            guard !Task.isCancelled else {
                return
            }
            for instance in instances {
                self.continuation.yield(instance)
            }
        }

        func yield(_ error: Error) {
            guard !Task.isCancelled else {
                return
            }
            self.continuation.yield(with: .failure(error))
        }

        static func == (lhs: Subscription, rhs: Subscription) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            self.id.hash(into: &hasher)
        }
    }

    private struct InstanceSequence: ServiceDiscoveryInstanceSequence {
        typealias Element = Instance
        typealias Underlying = AsyncThrowingStream<Instance, Error>

        private let underlying: Underlying

        init(_ underlying: AsyncThrowingStream<Instance, Error>) {
            self.underlying = underlying
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(self.underlying.makeAsyncIterator())
        }

        struct AsyncIterator: AsyncIteratorProtocol {
            private var underlying: Underlying.AsyncIterator

            init(_ iterator: Underlying.AsyncIterator) {
                self.underlying = iterator
            }

            mutating func next() async throws -> Instance? {
                try await self.underlying.next()
            }
        }
    }
}

public extension InMemoryServiceDiscovery {
    struct Configuration {
        public let instances: [Service: [Instance]]

        /// Default configuration
        public static var `default`: Configuration {
            .init(
                instances: [:]
            )
        }

        public init(
            instances: [Service: [Instance]]
        ) {
            self.instances = instances
        }
    }
}

