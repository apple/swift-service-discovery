//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

#if compiler(>=5.5) && canImport(_Concurrency)

public extension ServiceDiscovery {
    /// Performs async lookup for the given service's instances.
    ///
    /// ``defaultLookupTimeout`` will be used to compute `deadline` in case one is not specified.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///
    /// -  Returns: A listing of service instances.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func lookup(_ service: Service, deadline: DispatchTime? = nil) async throws -> [Instance] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Instance], Error>) in
            self.lookup(service, deadline: deadline) { result in
                switch result {
                case .success(let instances):
                    continuation.resume(returning: instances)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Returns a ``ServiceSnapshots``, which is an `AsyncSequence` and each of its items is a snapshot listing of service instances.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///
    /// -  Returns: A ``ServiceSnapshots`` async sequence.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func subscribe(to service: Service) -> ServiceSnapshots<Instance> {
        ServiceSnapshots(AsyncThrowingStream<[Instance], Error> { continuation in
            Task {
                let cancellationToken = self.subscribe(
                    to: service,
                    onNext: { result in
                        switch result {
                        case .success(let instances):
                            continuation.yield(instances)
                        case .failure(let error):
                            // LookupError is recoverable (e.g., service is added *after* subscription begins), so don't give up yet
                            guard error is LookupError else {
                                return continuation.finish(throwing: error)
                            }
                        }
                    },
                    onComplete: { reason in
                        switch reason {
                        case .cancellationRequested:
                            continuation.finish()
                        case .serviceDiscoveryUnavailable:
                            continuation.finish(throwing: ServiceDiscoveryError.unavailable)
                        default:
                            continuation.finish(throwing: ServiceDiscoveryError.other(reason.description))
                        }
                    }
                )

                continuation.onTermination = { @Sendable (_) -> Void in
                    cancellationToken.cancel()
                }
            }
        })
    }
}

/// An async sequence of snapshot listings of service instances.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct ServiceSnapshots<Instance>: AsyncSequence {
    public typealias Element = [Instance]
    typealias AsyncSnapshotsStream = AsyncThrowingStream<Element, Error>

    private let stream: AsyncSnapshotsStream

    public init<SnapshotSequence: AsyncSequence>(_ snapshots: SnapshotSequence) where SnapshotSequence.Element == Element {
        self.stream = AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await snapshot in snapshots {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(self.stream.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var underlying: AsyncSnapshotsStream.Iterator

        init(_ iterator: AsyncSnapshotsStream.Iterator) {
            self.underlying = iterator
        }

        public mutating func next() async throws -> [Instance]? {
            try await self.underlying.next()
        }
    }
}

#endif
