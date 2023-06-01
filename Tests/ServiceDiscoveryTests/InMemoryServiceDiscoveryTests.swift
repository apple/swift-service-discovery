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
    typealias Service = String
    typealias Instance = HostPort

    static let fooService = "fooService"
    static let fooInstances = [
        HostPort(host: "localhost", port: 7001),
    ]

    static let barService = "bar-service"
    static let barInstances = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    func testLookup() async throws {
        let configuration = InMemoryServiceDiscovery.Configuration(
            instances: [
                Self.fooService: Self.fooInstances,
                Self.barService: Self.barInstances,
            ]
        )

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let fooInstances = try await serviceDiscovery.lookup(Self.fooService, deadline: .none)
        XCTAssertEqual(fooInstances, Self.fooInstances, "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(fooInstances)")

        let barInstances = try await serviceDiscovery.lookup(Self.barService, deadline: .none)
        XCTAssertEqual(barInstances, Self.barInstances, "Expected service[\(Self.barService)] to have instances \(Self.barInstances), got \(barInstances)")
    }

    func testLookupErrorIfServiceUnknown() async throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(
            instances: ["foo-service": []]
        )
        let serviceDiscovery = InMemoryServiceDiscovery<Service, Instance>(configuration: configuration)

        await XCTAssertThrowsErrorAsync(try await serviceDiscovery.lookup(unknownService, deadline: .none)) { error in
            guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
                return XCTFail("Expected LookupError.unknownService, got \(error)")
            }
        }
    }

    func testSubscribe() async throws {
        let configuration = InMemoryServiceDiscovery.Configuration(
            instances: [Self.fooService: Self.fooInstances]
        )
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let barInstances: [HostPort] = [
            .init(host: "localhost", port: 8081),
            .init(host: "localhost", port: 8082),
            .init(host: "localhost", port: 8083),
        ]

        let counter = ManagedAtomic<Int>(0)

        #if os(macOS)
        let expectation = XCTestExpectation(description: #function)
        #else
        let semaphore = DispatchSemaphore(value: 0)
        #endif

        await serviceDiscovery.register(service: Self.barService, instances: [barInstances[0]])

        let task = Task {
            for try await instance in try await serviceDiscovery.subscribe(Self.barService) {
                switch counter.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    // FIXME: casting to HostPort due to a 5.9 compiler bug
                    XCTAssertEqual(instance as? HostPort, barInstances[0])
                    await serviceDiscovery.register(service: Self.barService, instances: Array(barInstances[1 ..< 3]))
                case 2:
                    // FIXME: casting to HostPort due to a 5.9 compiler bug
                    XCTAssertEqual(instance as? HostPort, barInstances[1])
                case 3:
                    // FIXME: casting to HostPort due to a 5.9 compiler bug
                    XCTAssertEqual(instance as? HostPort, barInstances[2])
                    #if os(macOS)
                    expectation.fulfill()
                    #else
                    semaphore.signal()
                    #endif
                default:
                    XCTFail("Expected to receive \(barInstances.count) instances")
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore.wait(timeout: .now() + 1.0))
        #endif
        task.cancel()

        XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), barInstances.count, "Expected to receive \(barInstances.count) instances")

        await serviceDiscovery.register(service: Self.barService, instances: Self.barInstances)

        XCTAssertEqual(counter.load(ordering: .sequentiallyConsistent), barInstances.count, "Expected to receive \(barInstances.count) instances")
    }

    func testCancellation() async throws {
        let configuration = InMemoryServiceDiscovery.Configuration(
            instances: [Self.fooService: Self.fooInstances]
        )
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let barInstances: [HostPort] = [
            .init(host: "localhost", port: 8081),
            .init(host: "localhost", port: 8082),
            .init(host: "localhost", port: 8083),
        ]

        #if os(macOS)
        let expectation1 = XCTestExpectation(description: #function)
        let expectation2 = XCTestExpectation(description: #function)
        #else
        let semaphore1 = DispatchSemaphore(value: 0)
        let semaphore2 = DispatchSemaphore(value: 0)
        #endif

        await serviceDiscovery.register(service: Self.barService, instances: [barInstances[0]])

        let counter1 = ManagedAtomic<Int>(0)
        let task1 = Task {
            for try await instance in try await serviceDiscovery.subscribe(Self.barService) {
                switch counter1.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertEqual(instance as? HostPort, barInstances[0])
                    #if os(macOS)
                    expectation1.fulfill()
                    #else
                    semaphore1.signal()
                    #endif
                default:
                    XCTFail("Expected to receive 1 instances")
                }
            }
        }

        let counter2 = ManagedAtomic<Int>(0)
        let task2 = Task {
            for try await instance in try await serviceDiscovery.subscribe(Self.barService) {
                switch counter2.wrappingIncrementThenLoad(ordering: .sequentiallyConsistent) {
                case 1:
                    XCTAssertEqual(instance as? HostPort, barInstances[0])
                case 2:
                    XCTAssertEqual(instance as? HostPort, barInstances[1])
                    #if os(macOS)
                    expectation2.fulfill()
                    #else
                    semaphore2.signal()
                    #endif
                default:
                    XCTFail("Expected to receive 2 instances")
                }
            }
        }

        #if os(macOS)
        await fulfillment(of: [expectation1], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore1.wait(timeout: .now() + 1.0))
        #endif
        task1.cancel()
        XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1, "Expected to receive \(barInstances.count) instances")
        XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 1, "Expected to receive \(barInstances.count) instances")

        await serviceDiscovery.register(service: Self.barService, instances: [barInstances[1]])
        #if os(macOS)
        await fulfillment(of: [expectation2], timeout: 1.0)
        #else
        XCTAssertEqual(.success, semaphore2.wait(timeout: .now() + 1.0))
        #endif
        task2.cancel()

        XCTAssertEqual(counter1.load(ordering: .sequentiallyConsistent), 1, "Expected to receive \(barInstances.count) instances")
        XCTAssertEqual(counter2.load(ordering: .sequentiallyConsistent), 2, "Expected to receive \(barInstances.count) instances")
    }
}
