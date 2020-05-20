//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
@testable import ServiceDiscovery
import ServiceDiscoveryHelpers
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

        let semaphore = DispatchSemaphore(value: 0)

        boxedServiceDiscovery.lookup(self.fooService) { fooResult in
            guard case .success(let _fooInstances) = fooResult else {
                return XCTFail("Failed to lookup instances for service[\(self.fooService)]")
            }
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

            semaphore.signal()
        }

        if semaphore.wait(timeout: DispatchTime.now() + .seconds(1)) == .timedOut {
            return XCTFail("Failed to lookup instances for service[\(self.fooService)]: timed out")
        }
    }

    func test_ServiceDiscoveryBox_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let boxedServiceDiscovery = ServiceDiscoveryBox<Service, Instance>(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = SDAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        boxedServiceDiscovery.subscribe(to: self.barService) { result in
            _ = resultCounter.add(1)

            guard resultCounter.load() <= 2 else {
                return XCTFail("Expected to receive result 2 times only")
            }

            switch result {
            case .failure(let error):
                guard resultCounter.load() == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                    return XCTFail("Expected the first result to be LookupError.unknownService since \(self.barService) is not registered, got \(error)")
                }
            case .success(let instances):
                guard resultCounter.load() == 2 else {
                    return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load()) got \(instances)")
                }
                XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.barService) to be \(self.barInstances), got \(instances)")
                semaphore.signal()
            }
        }

        serviceDiscovery.register(self.barService, instances: self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(), 2, "Expected to receive result 2 times, got \(resultCounter.load())")
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

        let semaphore = DispatchSemaphore(value: 0)

        anyServiceDiscovery.lookupAndUnwrap(self.fooService) { (fooResult: Result<[Instance], Error>) in
            guard case .success(let _fooInstances) = fooResult else {
                return XCTFail("Failed to lookup instances for service[\(self.fooService)]")
            }
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

            semaphore.signal()
        }

        if semaphore.wait(timeout: DispatchTime.now() + .seconds(1)) == .timedOut {
            return XCTFail("Failed to lookup instances for service[\(self.fooService)]: timed out")
        }
    }

    func test_AnyServiceDiscovery_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = SDAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        anyServiceDiscovery.subscribe(to: self.barService) { result in
            _ = resultCounter.add(1)

            guard resultCounter.load() <= 2 else {
                return XCTFail("Expected to receive result 2 times only")
            }

            switch result {
            case .failure(let error):
                guard resultCounter.load() == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                    return XCTFail("Expected the first result to be LookupError.unknownService since \(self.barService) is not registered, got \(error)")
                }
            case .success(let instances):
                guard resultCounter.load() == 2 else {
                    return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load()) got \(instances)")
                }
                XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.barService) to be \(self.barInstances), got \(instances)")
                semaphore.signal()
            }
        }

        serviceDiscovery.register(self.barService, instances: self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(), 2, "Expected to receive result 2 times, got \(resultCounter.load())")
    }

    func test_AnyServiceDiscovery_unwrap() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let anyServiceDiscovery = AnyServiceDiscovery(serviceDiscovery)

        XCTAssertNoThrow(try anyServiceDiscovery.unwrapAs(InMemoryServiceDiscovery<Service, Instance>.self))
    }
}
