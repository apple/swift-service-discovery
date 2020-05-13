//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftServiceDiscovery project authors
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

class InMemoryServiceDiscoveryTests: XCTestCase {
    typealias Service = String
    typealias Instance = HostPort

    func test_lookup() throws {
        let fooService = "fooService"
        let fooInstances = [
            HostPort(host: "localhost", port: 7001),
        ]

        let barService = "bar-service"
        let barInstances = [
            HostPort(host: "localhost", port: 9001),
            HostPort(host: "localhost", port: 9002),
        ]

        var configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: fooInstances])
        configuration.register(service: barService, instances: barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        defer { serviceDiscovery.shutdown() }

        let fooResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: fooService)
        guard case .success(let _fooInstances) = fooResult else {
            return XCTFail("Failed to lookup instances for service[\(fooService)]")
        }
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(fooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, fooInstances, "Expected service[\(fooService)] to have instances \(fooInstances), got \(_fooInstances)")

        let barResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: barService)
        guard case .success(let _barInstances) = barResult else {
            return XCTFail("Failed to lookup instances for service[\(barService)]")
        }
        XCTAssertEqual(_barInstances.count, 2, "Expected service[\(barService)] to have 2 instances, got \(_barInstances.count)")
        XCTAssertEqual(_barInstances, barInstances, "Expected service[\(barService)] to have instances \(barInstances), got \(_barInstances)")
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery<Service, Instance>(configuration: configuration)
        defer { serviceDiscovery.shutdown() }

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: unknownService)
        guard case .failure(let error) = result else {
            return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
        }
        guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
            return XCTFail("Expected LookupError.unknownService, got \(error)")
        }
    }

    func test_subscribe() throws {
        let fooService = "fooService"
        let fooInstances = [
            HostPort(host: "localhost", port: 7001),
        ]

        let barService = "bar-service"
        let barInstances = [
            HostPort(host: "localhost", port: 9001),
            HostPort(host: "localhost", port: 9002),
        ]

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: fooInstances])
        var serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        defer { serviceDiscovery.shutdown() }

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = SDAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        serviceDiscovery.subscribe(service: barService) { result in
            _ = resultCounter.add(1)

            guard resultCounter.load() <= 2 else {
                return XCTFail("Expected to receive result 2 times only")
            }

            switch result {
            case .failure(let error):
                guard resultCounter.load() == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                    return XCTFail("Expected the first result to be LookupError.unknownService since \(barService) is not registered, got \(error)")
                }
            case .success(let instances):
                guard resultCounter.load() == 2 else {
                    return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load()) got \(instances)")
                }
                XCTAssertEqual(instances, barInstances, "Expected instances of \(barService) to be \(barInstances), got \(instances)")
                semaphore.signal()
            }
        }

        serviceDiscovery.register(service: barService, instances: barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(), 2, "Expected to receive result 2 times, got \(resultCounter.load())")
    }

    private func ensureResult(serviceDiscovery: InMemoryServiceDiscovery<Service, Instance>, service: Service) throws -> Result<[Instance], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[Instance], Error>?

        serviceDiscovery.lookup(service: service) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        guard let _result = result else {
            throw LookupError.timedOut
        }

        return _result
    }
}
