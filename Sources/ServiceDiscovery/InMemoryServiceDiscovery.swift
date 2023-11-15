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

public actor InMemoryServiceDiscovery<Instance>: ServiceDiscovery, ServiceDiscoverySubscription {
    private var instances: [Instance]
    private var nextSubscriptionID = 0
    private var subscriptions: [Int: AsyncStream<Result<[Instance], Error>>.Continuation]

    public init(instances: [Instance] = []) {
        self.instances = instances
        self.subscriptions = [:]
    }

    /// ServiceDiscovery implementation
    /// Performs async lookup for the given service's instances.
    public func lookup() async throws -> [Instance] {
        self.instances
    }

    /// ServiceDiscovery implementation
    /// Subscribes to receive a service's instances whenever they change.
    public func subscribe() async throws -> InMemoryServiceDiscovery {
        self
    }

    /// ServiceDiscoverySubscription implementation, provides an AsyncSequence to consume
    public func next() async -> _DiscoverySequence {
        defer { self.nextSubscriptionID += 1 }
        let subscriptionID = self.nextSubscriptionID

        let (stream, continuation) = AsyncStream.makeStream(of: Result<[Instance], Error>.self)
        continuation.onTermination = { _ in
            Task {
                await self.unsubscribe(subscriptionID: subscriptionID)
            }
        }

        self.subscriptions[subscriptionID] = continuation

        do {
            let instances = try await self.lookup()
            continuation.yield(.success(instances))
        } catch {
            continuation.yield(.failure(error))
        }

        return _DiscoverySequence(stream)
    }

    /// Registers  new `instances`.
    public func register(instances: [Instance]) {
        self.instances = instances

        for continuations in self.subscriptions.values {
            continuations.yield(.success(instances))
        }
    }

    private func unsubscribe(subscriptionID: Int) {
        self.subscriptions.removeValue(forKey: subscriptionID)
    }

    /// Internal use only
    public struct _DiscoverySequence: AsyncSequence {
        public typealias Element = Result<[Instance], Error>

        private var underlying: AsyncStream<Result<[Instance], Error>>

        init(_ underlying: AsyncStream<Result<[Instance], Error>>) {
            self.underlying = underlying
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(self.underlying.makeAsyncIterator())
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var underlying: AsyncStream<Result<[Instance], Error>>.Iterator

            init(_ underlying: AsyncStream<Result<[Instance], Error>>.Iterator) {
                self.underlying = underlying
            }

            public mutating func next() async -> Result<[Instance], Error>? {
                await self.underlying.next()
            }
        }
    }
}

#if swift(<5.9)
// Async stream API backfill
extension AsyncStream {
    public static func makeStream(
        of elementType: Element.Type = Element.self,
        bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncStream<Element>, continuation: AsyncStream<Element>.Continuation) {
        var continuation: AsyncStream<Element>.Continuation!
        let stream = AsyncStream<Element>(bufferingPolicy: limit) { continuation = $0 }
        return (stream: stream, continuation: continuation!)
    }
}
#endif
