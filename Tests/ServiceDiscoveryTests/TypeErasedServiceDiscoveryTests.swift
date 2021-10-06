//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import Dispatch
@testable import ServiceDiscovery
import XCTest

class TypeErasedServiceDiscoveryTests: XCTestCase {
    typealias Service = String
    typealias Instance = HostPort

    let fooService = "fooService"
    let fooInstances = [
        HostPort(host: "localhost", port: 7001),
    ]

    let barService = "bar-service"
    let barInstances = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    func test_ServiceDiscoveryBox_lookup() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        runAsyncAndWaitFor {
            let _fooInstances = try await boxedServiceDiscovery.lookup(self.fooService)
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")
        }
    }

    func test_ServiceDiscoveryBox_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let counter = ManagedAtomic<Int>(0)

        Task.detached {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            serviceDiscovery.register(self.barService, instances: [])
            usleep(50000)
            // Update #2
            serviceDiscovery.register(self.barService, instances: self.barInstances)
        }

        let task = Task.detached { () -> Void in
            do {
                for try await instances in try boxedServiceDiscovery.subscribe(to: self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(self.barService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.barService) to be \(self.barInstances), got \(instances)")
                        // This causes the stream to terminate
                        serviceDiscovery.shutdown()
                    default:
                        XCTFail("Expected to receive instances 2 times")
                    }
                }
            } catch {
                switch counter.load(ordering: .relaxed) {
                case 2: // shutdown is called after receiving two results
                    guard let serviceDiscoveryError = error as? ServiceDiscoveryError, serviceDiscoveryError == .unavailable else {
                        return XCTFail("Expected ServiceDiscoveryError.unavailable, got \(error)")
                    }
                    // Test is complete at this point
                    semaphore.signal()
                default:
                    XCTFail("Unexpected error \(error)")
                }
            }
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        task.cancel()

        XCTAssertEqual(counter.load(ordering: .relaxed), 2, "Expected to receive instances 2 times, got \(counter.load(ordering: .relaxed)) times")
    }

    func test_ServiceDiscoveryBox_unwrap() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        XCTAssertNoThrow(try boxedServiceDiscovery.unwrapAs(InMemoryServiceDiscovery<Service, Instance>.self))
    }

    func test_AnyServiceDiscovery_lookup() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        runAsyncAndWaitFor {
            let _fooInstances: [Instance] = try await anyServiceDiscovery.lookupAndUnwrap(self.fooService)
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")
        }
    }

    func test_AnyServiceDiscovery_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let counter = ManagedAtomic<Int>(0)

        Task.detached {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            serviceDiscovery.register(self.barService, instances: [])
            usleep(50000)
            // Update #2
            serviceDiscovery.register(self.barService, instances: self.barInstances)
        }

        let task = Task.detached { () -> Void in
            do {
                for try await instances: [Instance] in try anyServiceDiscovery.subscribeAndUnwrap(to: self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(self.barService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.barService) to be \(self.barInstances), got \(instances)")
                        // This causes the stream to terminate
                        serviceDiscovery.shutdown()
                    default:
                        XCTFail("Expected to receive instances 2 times")
                    }
                }
            } catch {
                switch counter.load(ordering: .relaxed) {
                case 2: // shutdown is called after receiving two results
                    guard let serviceDiscoveryError = error as? ServiceDiscoveryError, serviceDiscoveryError == .unavailable else {
                        return XCTFail("Expected ServiceDiscoveryError.unavailable, got \(error)")
                    }
                    // Test is complete at this point
                    semaphore.signal()
                default:
                    XCTFail("Unexpected error \(error)")
                }
            }
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        task.cancel()

        XCTAssertEqual(counter.load(ordering: .relaxed), 2, "Expected to receive instances 2 times, got \(counter.load(ordering: .relaxed)) times")
    }

    func test_AnyServiceDiscovery_unwrap() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        XCTAssertNoThrow(try anyServiceDiscovery.unwrapAs(InMemoryServiceDiscovery<Service, Instance>.self))
    }
}
