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

class MapInstanceServiceDiscoveryTests: XCTestCase {
    typealias Service = String
    typealias BaseInstance = Int
    typealias DerivedInstance = HostPort

    let fooService = "fooService"
    let fooBaseInstances = [
        7001,
    ]
    let fooDerivedInstances = [
        HostPort(host: "localhost", port: 7001),
    ]

    let barService = "bar-service"
    let barBaseInstances = [
        9001,
        9002,
    ]
    let barDerivedInstances = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    func test_lookup() throws {
        var configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        configuration.register(service: self.barService, instances: self.barBaseInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { port in HostPort(host: "localhost", port: port) }

        runAsyncAndWaitFor {
            let _fooInstances = try await serviceDiscovery.lookup(self.fooService)
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooDerivedInstances, "Expected service[\(self.fooService)] to have instances \(self.fooDerivedInstances), got \(_fooInstances)")

            let _barInstances = try await serviceDiscovery.lookup(self.barService)
            XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.barService)] to have 2 instances, got \(_barInstances.count)")
            XCTAssertEqual(_barInstances, self.barDerivedInstances, "Expected service[\(self.barService)] to have instances \(self.barDerivedInstances), got \(_barInstances)")
        }
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { port in HostPort(host: "localhost", port: port) }

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
        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapInstance { port in HostPort(host: "localhost", port: port) }

        let semaphore = DispatchSemaphore(value: 0)
        let counter = ManagedAtomic<Int>(0)

        Task.detached {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            baseServiceDiscovery.register(self.barService, instances: [])
            usleep(50000)
            // Update #2
            baseServiceDiscovery.register(self.barService, instances: self.barBaseInstances)
        }

        let task = Task.detached { () -> Void in
            do {
                for try await instances in try serviceDiscovery.subscribe(to: self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(self.barService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, self.barDerivedInstances, "Expected instances of \(self.barService) to be \(self.barDerivedInstances), got \(instances)")
                        // This causes the stream to terminate
                        baseServiceDiscovery.shutdown()
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
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let baseServiceDisovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDisovery.mapInstance { port in HostPort(host: "localhost", port: port) }

        let registerSemaphore = DispatchSemaphore(value: 0)
        let registerCounter = ManagedAtomic<Int>(0)

        let lookupSemaphore = DispatchSemaphore(value: 0)
        let lookupCounter = ManagedAtomic<Int>(0)

        let times = 100

        Task.detached {
            await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 1 ... times {
                    group.addTask {
                        baseServiceDisovery.register(self.fooService, instances: self.fooBaseInstances)
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
                        XCTAssertEqual(instances, self.fooDerivedInstances, "Expected service[\(self.fooService)] to have instances \(self.fooDerivedInstances), got \(instances)")

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

    func testThrownErrorsPropagateIntoFailures() throws {
        enum TestError: Error {
            case error
        }

        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { _ -> Int in throw TestError.error }

        runAsyncAndWaitFor {
            do {
                let instances = try await serviceDiscovery.lookup(self.fooService)
                XCTFail("Expected failure, got \(instances)")
            } catch {
                XCTAssertEqual(error as? TestError, .error, "Expected \(TestError.error), but got \(error)")
            }
        }
    }

    func testPropagateDefaultTimeout() throws {
        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { port in HostPort(host: "localhost", port: port) }
        XCTAssertTrue(compareTimeInterval(configuration.defaultLookupTimeout, serviceDiscovery.defaultLookupTimeout), "\(configuration.defaultLookupTimeout) does not match \(serviceDiscovery.defaultLookupTimeout)")
    }
}
