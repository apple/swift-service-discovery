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

public actor InMemoryServiceDiscovery<Instance>: ServiceDiscovery {

    private let configuration: Configuration

    private var instances: [Instance]
    private var subscriptions: Set<Subscription>

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.instances = configuration.instances
        self.subscriptions = []
    }

    public func lookup() async throws -> [Instance] {
        return self.instances
    }

    public func subscribe() async throws -> any ServiceDiscoveryInstancesSequence {
        let (subscription, sequence) = Subscription.makeSubscription(terminationHandler: { subscription in
            Task {
                await self.unsubscribe(subscription: subscription)
            }
        })

        // reduce CoW
        self.subscriptions.insert(subscription)

        do {
            let instances = try await self.lookup()
            subscription.yield(instances)
        } catch {
            subscription.yield(error)
        }

        return sequence
    }

    private func unsubscribe(subscription: Subscription) {
        self.subscriptions.remove(subscription)
    }

    /// Registers  new `instances`.
    public func register(instances: [Instance]) async {
        self.instances = instances

        for subscription in self.subscriptions {
            subscription.yield(instances)
        }
    }

    private class Subscription: Identifiable, Hashable {
        private let continuation: AsyncThrowingStream<[Instance], Error>.Continuation

        static func makeSubscription(terminationHandler: @Sendable @escaping (Subscription) -> Void) -> (Subscription, InstancesSequence) {
            #if swift(<5.9)
            var continuation: AsyncThrowingStream<[Instance], Error>.Continuation!
            let stream = AsyncThrowingStream { _continuation in
                continuation = _continuation
            }
            #else
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Instance].self)
            #endif
            let subscription = Subscription(continuation)
            continuation.onTermination = { @Sendable _ in terminationHandler(subscription) }
            return (subscription, InstancesSequence(stream))
        }

        private init(_ continuation: AsyncThrowingStream<[Instance], Error>.Continuation) {
            self.continuation = continuation
        }

        func yield(_ instances: [Instance]) {
            guard !Task.isCancelled else {
                return
            }
            self.continuation.yield(instances)
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

    private struct InstancesSequence: ServiceDiscoveryInstancesSequence {
        typealias Element = [Instance]
        typealias Underlying = AsyncThrowingStream<[Instance], Error>

        private let underlying: Underlying

        init(_ underlying: AsyncThrowingStream<[Instance], Error>) {
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

            mutating func next() async throws -> [Instance]? {
                try await self.underlying.next()
            }
        }
    }
}

public extension InMemoryServiceDiscovery {
    struct Configuration {
        public let instances: [Instance]

        /// Default configuration
        public static var `default`: Configuration {
            .init(
                instances: []
            )
        }

        public init(
            instances: [Instance]
        ) {
            self.instances = instances
        }
    }
}

