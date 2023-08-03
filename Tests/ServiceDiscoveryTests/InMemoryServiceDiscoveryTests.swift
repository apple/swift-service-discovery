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
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = try await serviceDiscovery.subscribe().makeAsyncIterator()
            while let instances = try await iterator.next() {
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
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = try await serviceDiscovery.subscribe().makeAsyncIterator()
            while let instances = try await iterator.next() {
                // for try await instances in try await serviceDiscovery.subscribe() {
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
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = try await serviceDiscovery.subscribe().makeAsyncIterator()
            while let instances = try await iterator.next() {
                // for try await instances in try await serviceDiscovery.subscribe() {
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

        let task3 = Task {
            // FIXME: using iterator instead of for..in due to 5.7 compiler bug
            var iterator = try await serviceDiscovery.subscribe().makeAsyncIterator()
            while let instances = try await iterator.next() {
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

        await serviceDiscovery.register(instances: Self.mockInstances1)
        #if os(macOS)
        await fulfillment(of: [expectation3], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore3.wait(timeout: .now() + 1.0))
        #endif
        task3.cancel()
    }
}
