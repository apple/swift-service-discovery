//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the SwiftServiceDiscovery project authors
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

    static let fooService = "fooService"
    static let fooInstances = [
        HostPort(host: "localhost", port: 7001),
    ]

    static let barService = "bar-service"
    static let barInstances = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    func test_ServiceDiscoveryBox_lookup() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)

        boxedServiceDiscovery.lookup(Self.fooService) { fooResult in
            guard case .success(let _fooInstances) = fooResult else {
                return XCTFail("Failed to lookup instances for service[\(Self.fooService)]")
            }
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, Self.fooInstances, "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)")

            semaphore.signal()
        }

        if semaphore.wait(timeout: DispatchTime.now() + .seconds(1)) == .timedOut {
            return XCTFail("Failed to lookup instances for service[\(Self.fooService)]: timed out")
        }
    }

    func test_ServiceDiscoveryBox_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = ManagedAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        boxedServiceDiscovery.subscribe(
            to: Self.barService,
            onNext: { result in
                resultCounter.wrappingIncrement(ordering: .relaxed)

                guard resultCounter.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                        return XCTFail("Expected the first result to be LookupError.unknownService since \(Self.barService) is not registered, got \(error)")
                    }
                case .success(let instances):
                    guard resultCounter.load(ordering: .relaxed) == 2 else {
                        return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load(ordering: .relaxed)) got \(instances)")
                    }
                    XCTAssertEqual(instances, Self.barInstances, "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)")
                    semaphore.signal()
                }
            }
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)
        serviceDiscovery.register(Self.barService, instances: Self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(ordering: .relaxed), 2, "Expected to receive result 2 times, got \(resultCounter.load(ordering: .relaxed))")
    }

    func test_ServiceDiscoveryBox_unwrap() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        XCTAssertNoThrow(try boxedServiceDiscovery.unwrapAs(InMemoryServiceDiscovery<Service, Instance>.self))
    }

    func test_AnyServiceDiscovery_lookup() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)

        anyServiceDiscovery.lookupAndUnwrap(Self.fooService) { (fooResult: Result<[Instance], Error>) in
            guard case .success(let _fooInstances) = fooResult else {
                return XCTFail("Failed to lookup instances for service[\(Self.fooService)]")
            }
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, Self.fooInstances, "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)")

            semaphore.signal()
        }

        if semaphore.wait(timeout: DispatchTime.now() + .seconds(1)) == .timedOut {
            return XCTFail("Failed to lookup instances for service[\(Self.fooService)]: timed out")
        }
    }

    func test_AnyServiceDiscovery_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = ManagedAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        anyServiceDiscovery.subscribeAndUnwrap(
            to: Self.barService,
            onNext: { (result: Result<[Instance], Error>) in
                resultCounter.wrappingIncrement(ordering: .relaxed)

                guard resultCounter.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                        return XCTFail("Expected the first result to be LookupError.unknownService since \(Self.barService) is not registered, got \(error)")
                    }
                case .success(let instances):
                    guard resultCounter.load(ordering: .relaxed) == 2 else {
                        return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load(ordering: .relaxed)) got \(instances)")
                    }
                    XCTAssertEqual(instances, Self.barInstances, "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)")
                    semaphore.signal()
                }
            }
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)
        serviceDiscovery.register(Self.barService, instances: Self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(ordering: .relaxed), 2, "Expected to receive result 2 times, got \(resultCounter.load(ordering: .relaxed))")
    }

    func test_AnyServiceDiscovery_unwrap() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        XCTAssertNoThrow(try anyServiceDiscovery.unwrapAs(InMemoryServiceDiscovery<Service, Instance>.self))
    }

    // MARK: - async/await API tests

    func test_ServiceDiscoveryBox_async_lookup() async throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let _fooInstances = try await boxedServiceDiscovery.lookup(Self.fooService)
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, Self.fooInstances, "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)")
    }

    func test_ServiceDiscoveryBox_async_subscribe() async throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let counter = ManagedAtomic<Int>(0)

        Task {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            serviceDiscovery.register(Self.barService, instances: [])
            usleep(50000)
            // Update #2
            serviceDiscovery.register(Self.barService, instances: Self.barInstances)
        }

        let task = Task { () in
            do {
                for try await instances in boxedServiceDiscovery.subscribe(to: Self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(Self.barService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, Self.barInstances, "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)")
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
                default:
                    XCTFail("Unexpected error \(error)")
                }
            }
        }

        _ = await task.result

        XCTAssertEqual(counter.load(ordering: .relaxed), 2, "Expected to receive instances 2 times, got \(counter.load(ordering: .relaxed)) times")
    }

    func test_AnyServiceDiscovery_async_lookup() async throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let _fooInstances: [Instance] = try await anyServiceDiscovery.lookupAndUnwrap(Self.fooService)
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, Self.fooInstances, "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)")
    }

    func test_AnyServiceDiscovery_async_subscribe() async throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let counter = ManagedAtomic<Int>(0)

        Task {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            serviceDiscovery.register(Self.barService, instances: [])
            usleep(50000)
            // Update #2
            serviceDiscovery.register(Self.barService, instances: Self.barInstances)
        }

        let task = Task { () in
            do {
                for try await instances: [Instance] in anyServiceDiscovery.subscribeAndUnwrap(to: Self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(Self.barService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, Self.barInstances, "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)")
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
                default:
                    XCTFail("Unexpected error \(error)")
                }
            }
        }

        _ = await task.result

        XCTAssertEqual(counter.load(ordering: .relaxed), 2, "Expected to receive instances 2 times, got \(counter.load(ordering: .relaxed)) times")
    }
}
