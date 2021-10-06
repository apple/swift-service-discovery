//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftServiceDiscovery project authors
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

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct ServiceSnapshots<Instance>: AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = [Instance]

    private let _next: () async throws -> [Instance]?

    public init<SnapshotSequence: AsyncSequence>(_ snapshots: SnapshotSequence) where SnapshotSequence.Element == Element {
        var iterator = snapshots.makeAsyncIterator()
        self._next = { try await iterator.next() }
    }

    public func next() async throws -> [Instance]? {
        try await self._next()
    }

    public func makeAsyncIterator() -> Self {
        self
    }
}

#endif
