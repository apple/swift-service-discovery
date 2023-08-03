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
    private var instances: [Instance]
    private var nextSubscriptionID = 0
    private var subscriptions: [Int: AsyncThrowingStream<[Instance], Error>.Continuation]

    public init(instances: [Instance] = []) {
        self.instances = instances
        self.subscriptions = [:]
    }

    public func lookup() async throws -> [Instance] {
        self.instances
    }

    public func subscribe() async throws -> _DiscoverySequence {
        defer { self.nextSubscriptionID += 1 }
        let subscriptionID = self.nextSubscriptionID

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Instance].self)
        continuation.onTermination = { _ in
            Task {
                await self.unsubscribe(subscriptionID: subscriptionID)
            }
        }

        self.subscriptions[subscriptionID] = continuation

        let instances = try await self.lookup()
        continuation.yield(instances)

        return DiscoverySequence(stream)
    }

    /// Registers  new `instances`.
    public func register(instances: [Instance]) {
        self.instances = instances

        for continuations in self.subscriptions.values {
            continuations.yield(instances)
        }
    }

    private func unsubscribe(subscriptionID: Int) {
        self.subscriptions.removeValue(forKey: subscriptionID)
    }

    /// Internal use only
    public struct _DiscoverySequence: AsyncSequence {
        public typealias Element = [Instance]

        private var underlying: AsyncThrowingStream<[Instance], Error>

        init(_ underlying: AsyncThrowingStream<[Instance], Error>) {
            self.underlying = underlying
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(self.underlying.makeAsyncIterator())
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var underlying: AsyncThrowingStream<[Instance], Error>.Iterator

            init(_ underlying: AsyncThrowingStream<[Instance], Error>.Iterator) {
                self.underlying = underlying
            }

            public mutating func next() async throws -> [Instance]? {
                try await self.underlying.next()
            }
        }
    }
}

#if swift(<5.9)
// Async stream API backfil
public extension AsyncThrowingStream {
    static func makeStream(
        of elementType: Element.Type = Element.self,
        throwing failureType: Failure.Type = Failure.self,
        bufferingPolicy limit: Continuation.BufferingPolicy = .unbounded
    ) -> (stream: AsyncThrowingStream<Element, Failure>, continuation: AsyncThrowingStream<Element, Failure>.Continuation) where Failure == Error {
        var continuation: AsyncThrowingStream<Element, Failure>.Continuation!
        let stream = AsyncThrowingStream<Element, Failure>(bufferingPolicy: limit) { continuation = $0 }
        return (stream: stream, continuation: continuation!)
    }
}
#endif
