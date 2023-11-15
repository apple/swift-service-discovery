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

import Atomics
#if os(macOS)
import Dispatch
#endif
@testable import ServiceDiscovery
import XCTest

class InMemoryServiceDiscoveryTests: XCTestCase {
    typealias Instance = HostPort

    static let mockInstances1 = [
        HostPort(host: "localhost", port: 7001),
        HostPort(host: "localhost", port: 7002),
        HostPort(host: "localhost", port: 7003),
    ]

    static let mockInstances2 = [
        HostPort(host: "localhost", port: 8001),
        HostPort(host: "localhost", port: 8002),
        HostPort(host: "localhost", port: 8003),
    ]

    func testLookup() async throws {
        let serviceDiscovery = InMemoryServiceDiscovery(instances: Self.mockInstances1)

        do {
            let result = try await serviceDiscovery.lookup()
            XCTAssertEqual(result, Self.mockInstances1, "Expected \(Self.mockInstances1)")
        }

        do {
            await serviceDiscovery.register(instances: Self.mockInstances2)
            let result = try await serviceDiscovery.lookup()
            XCTAssertEqual(result, Self.mockInstances2, "Expected \(Self.mockInstances2)")
        }
    }

    func testSubscribe() async throws {
        let serviceDiscovery = InMemoryServiceDiscovery(instances: Self.mockInstances1)

        let counter = ManagedAtomic<Int>(0)

        #if os(macOS)
        let expectation = XCTestExpectation(description: #function)
        #else
        let semaphore = DispatchSemaphore(value: 0)
        #endif

        await serviceDiscovery.register(instances: [Self.mockInstances2[0]])

        let task = Task {
            let subscription = try await serviceDiscovery.subscribe()
            // for await result in await subscription.next() {
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = await subscription.next().makeAsyncIterator()
            while let result = await iterator.next() {
                let instances = try result.get()
                // for try await instances in try await serviceDiscovery.subscribe() {
                switch counter.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertEqual(instances.count, 1)
                    XCTAssertEqual(instances[0], Self.mockInstances2[0])
                    await serviceDiscovery.register(instances: [Self.mockInstances2[1]])
                case 2:
                    XCTAssertEqual(instances.count, 1)
                    XCTAssertEqual(instances[0], Self.mockInstances2[1])
                    await serviceDiscovery.register(instances: Self.mockInstances2)
                case 3:
                    XCTAssertEqual(instances.count, Self.mockInstances2.count)
                    XCTAssertEqual(instances, Self.mockInstances2)
                    #if os(macOS)
                    expectation.fulfill()
                    #else
                    semaphore.signal()
                    #endif
                default:
                    XCTFail("Expected to be called 3 times")
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore.wait(timeout: .now() + 1.0))
        #endif

        XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), 3, "Expected to be called 3 times")

        task.cancel()
        await serviceDiscovery.register(instances: Self.mockInstances2)

        XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), 3, "Expected to be called 3 times")
    }

    func testSubscribeWithErrors() async throws {
        let serviceDiscovery = ThrowingServiceDiscovery()

        let counter = ManagedAtomic<Int>(0)

        #if os(macOS)
        let expectation = XCTestExpectation(description: #function)
        #else
        let semaphore = DispatchSemaphore(value: 0)
        #endif

        let task = Task {
            let subscription = try await serviceDiscovery.subscribe()
            // for await result in await subscription.next() {
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = await subscription.next().makeAsyncIterator()
            while let result = await iterator.next() {
                switch counter.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertNoThrow(try result.get())
                    await serviceDiscovery.yield(error: DiscoveryError(description: "error 1"))
                case 2:
                    XCTAssertThrowsError(try result.get()) { error in
                        XCTAssertEqual(error as? DiscoveryError, DiscoveryError(description: "error 1"))
                    }
                    await serviceDiscovery.yield(instances: [(), (), ()])
                case 3:
                    XCTAssertNoThrow(try result.get())
                    XCTAssertEqual(try result.get().count, 3)
                    await serviceDiscovery.yield(error: DiscoveryError(description: "error 2"))
                case 4:
                    XCTAssertThrowsError(try result.get()) { error in
                        XCTAssertEqual(error as? DiscoveryError, DiscoveryError(description: "error 2"))
                    }
                    #if os(macOS)
                    expectation.fulfill()
                    #else
                    semaphore.signal()
                    #endif
                default:
                    XCTFail("Expected to be called 3 times")
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation], timeout: 5.0)
        #else
        XCTAssertEqual(.success, semaphore.wait(timeout: .now() + 1.0))
        #endif

        XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), 4, "Expected to be called 5 times")

        task.cancel()
    }

    func testCancellation() async throws {
        let serviceDiscovery = InMemoryServiceDiscovery(instances: Self.mockInstances1)

        #if os(macOS)
        let expectation1 = XCTestExpectation(description: #function)
        let expectation2 = XCTestExpectation(description: #function)
        let expectation3 = XCTestExpectation(description: #function)
        #else
        let semaphore1 = DispatchSemaphore(value: 0)
        let semaphore2 = DispatchSemaphore(value: 0)
        let semaphore3 = DispatchSemaphore(value: 0)
        #endif

        await serviceDiscovery.register(instances: [Self.mockInstances2[0]])

        let counter1 = ManagedAtomic<Int>(0)
        let counter2 = ManagedAtomic<Int>(0)

        let task1 = Task {
            let subscription = try await serviceDiscovery.subscribe()
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            // for await result in await subscription.next() {
            var iterator = await subscription.next().makeAsyncIterator()
            while let result = await iterator.next() {
                let instances = try result.get()
                switch counter1.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertEqual(instances.count, 1)
                    XCTAssertEqual(instances[0], Self.mockInstances2[0])
                    if counter2.load(ordering: .sequentiallyConsistent) == 1 {
                        #if os(macOS)
                        expectation1.fulfill()
                        #else
                        semaphore1.signal()
                        #endif
                    }
                default:
                    XCTFail("Expected to be called 1 time")
                }
            }
        }

        let task2 = Task {
            let subscription = try await serviceDiscovery.subscribe()
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            // for await result in await subscription.next() {
            var iterator = await subscription.next().makeAsyncIterator()
            while let result = await iterator.next() {
                let instances = try result.get()
                // FIXME: casting to HostPort due to a 5.9 compiler bug
                switch counter2.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertEqual(instances.count, 1)
                    XCTAssertEqual(instances[0], Self.mockInstances2[0])
                    if counter1.load(ordering: .sequentiallyConsistent) == 1 {
                        #if os(macOS)
                        expectation1.fulfill()
                        #else
                        semaphore1.signal()
                        #endif
                    }
                case 2:
                    XCTAssertEqual(instances.count, Self.mockInstances2.count)
                    XCTAssertEqual(instances, Self.mockInstances2)
                    #if os(macOS)
                    expectation2.fulfill()
                    #else
                    semaphore2.signal()
                    #endif
                default:
                    XCTFail("Expected to be called 2 times")
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation1], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore1.wait(timeout: .now() + 1.0))
        #endif
        task1.cancel()

        XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1, "Expected to be called 1 time")
        XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 1, "Expected to be called 1 time")

        await serviceDiscovery.register(instances: Self.mockInstances2)
        #if os(macOS)
        await fulfillment(of: [expectation2], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore2.wait(timeout: .now() + 1.0))
        #endif
        task2.cancel()

        XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1, "Expected to be called 1 time")
        XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 2, "Expected to be called 2 times")

        // one more time

        await serviceDiscovery.register(instances: Self.mockInstances1)

        let task3 = Task {
            let subscription = try await serviceDiscovery.subscribe()
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            // for await result in await subscription.next() {
            var iterator = await subscription.next().makeAsyncIterator()
            while let result = await iterator.next() {
                let instances = try result.get()
                XCTAssertEqual(instances.count, Self.mockInstances1.count)
                XCTAssertEqual(instances, Self.mockInstances1)
                if counter1.load(ordering: .sequentiallyConsistent) == 1 {
                    #if os(macOS)
                    expectation3.fulfill()
                    #else
                    semaphore3.signal()
                    #endif
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation3], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore3.wait(timeout: .now() + 1.0))
        #endif
        task3.cancel()
    }
}

private actor ThrowingServiceDiscovery: ServiceDiscovery, ServiceDiscoverySubscription {
    var continuation: AsyncStream<Result<[Void], Error>>.Continuation?

    func lookup() async throws -> [Void] {
        []
    }

    func subscribe() async throws -> ThrowingServiceDiscovery {
        self
    }

    func next() async -> InMemoryServiceDiscovery<Void>.DiscoverySequence {
        let (stream, continuation) = AsyncStream.makeStream(of: Result<[Void], Error>.self)
        self.continuation = continuation
        continuation.yield(.success([])) // get us going
        return InMemoryServiceDiscovery.DiscoverySequence(stream)
    }

    func yield(error: Error) {
        if let continuation = self.continuation {
            continuation.yield(.failure(error))
        }
    }

    func yield(instances: [Void]) {
        if let continuation = self.continuation {
            continuation.yield(.success(instances))
        }
    }
}

private struct DiscoveryError: Error, Equatable {
    let description: String
}
