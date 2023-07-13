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
    private var nextSubscriptionID = 0
    private var subscriptions: [Int: AsyncThrowingStream<[Instance], Error>.Continuation]

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.instances = configuration.instances
        self.subscriptions = [:]
    }

    public func lookup() -> [Instance] {
        self.instances
    }

    public func subscribe() -> Subscription {
        defer { self.nextSubscriptionID += 1 }
        let subscriptionID = self.nextSubscriptionID

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [Instance].self)
        continuation.onTermination = { _ in
            Task {
                await self.unsubscribe(subscriptionID: subscriptionID)
            }
        }

        self.subscriptions[subscriptionID] = continuation

        let instances = self.lookup()
        continuation.yield(instances)

        return Subscription(stream)
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

    public struct Subscription: AsyncSequence {
        public typealias Element = [Instance]

        private var backing: AsyncThrowingStream<[Instance], Error>

        init(_ backing: AsyncThrowingStream<[Instance], Error>) {
            self.backing = backing
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(self.backing.makeAsyncIterator())
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var backing: AsyncThrowingStream<[Instance], Error>.Iterator

            init(_ backing: AsyncThrowingStream<[Instance], Error>.Iterator) {
                self.backing = backing
            }

            public mutating func next() async throws -> [Instance]? {
                try await self.backing.next()
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

#if swift(<5.9)
// Async stream API backfil
extension AsyncThrowingStream {
    public static func makeStream(
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
