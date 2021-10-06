//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftServiceDiscovery project authors
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

class InMemoryServiceDiscoveryTests: XCTestCase {
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

    func test_lookup() throws {
        var configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        configuration.register(service: self.barService, instances: self.barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        runAsyncAndWaitFor {
            let _fooInstances = try await serviceDiscovery.lookup(self.fooService)
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

            let _barInstances = try await serviceDiscovery.lookup(self.barService)
            XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.barService)] to have 2 instances, got \(_barInstances.count)")
            XCTAssertEqual(_barInstances, self.barInstances, "Expected service[\(self.barService)] to have instances \(self.barInstances), got \(_barInstances)")
        }
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        runAsyncAndWaitFor {
            do {
                _ = try await serviceDiscovery.lookup(unknownService)
                return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
            } catch {
                guard let lookupError = error as? LookupError, lookupError == .unknownService else {
                    return XCTFail("Expected LookupError.unknownService, got \(error)")
                }
            }
        }
    }

    func test_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

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
                for try await instances in try serviceDiscovery.subscribe(to: self.barService) {
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

    func test_concurrency() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let registerSemaphore = DispatchSemaphore(value: 0)
        let registerCounter = ManagedAtomic<Int>(0)

        let lookupSemaphore = DispatchSemaphore(value: 0)
        let lookupCounter = ManagedAtomic<Int>(0)

        let times = 100

        Task.detached {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 1 ... times {
                    group.addTask {
                        serviceDiscovery.register(self.fooService, instances: self.fooInstances)
                        if registerCounter.wrappingIncrementThenLoad(ordering: .relaxed) == times {
                            registerSemaphore.signal()
                        }
                    }
                }
            }
        }

        Task.detached {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 1 ... times {
                    group.addTask {
                        let instances = try await serviceDiscovery.lookup(self.fooService)
                        XCTAssertEqual(instances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(instances)")

                        if lookupCounter.wrappingIncrementThenLoad(ordering: .relaxed) == times {
                            lookupSemaphore.signal()
                        }
                    }
                }
            }
        }

        _ = registerSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        _ = lookupSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        XCTAssertEqual(registerCounter.load(ordering: .relaxed), times, "Expected register to succeed \(times) times")
        XCTAssertEqual(lookupCounter.load(ordering: .relaxed), times, "Expected lookup callback to be called \(times) times")
    }
}
