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
import XCTest

class StaticServiceDiscoveryTests: XCTestCase {
    typealias Service = String
    typealias Instance = HostPort

    func test_lookup() throws {
        let fooService = "fooService"
        let fooInstances: Set<Instance> = [
            HostPort(host: "localhost", port: 7001),
        ]

        let barService = "bar-service"
        let barInstances: Set<Instance> = [
            HostPort(host: "localhost", port: 9001),
            HostPort(host: "localhost", port: 9002),
        ]

        var configuration = StaticServiceDiscovery<Service, Instance>.Configuration(instances: [fooService: fooInstances])
        configuration.register(service: barService, instances: barInstances)

        let serviceDiscovery = StaticServiceDiscovery(configuration: configuration)
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

        let configuration = StaticServiceDiscovery<Service, Instance>.Configuration(instances: ["foo-service": []])
        let serviceDiscovery = StaticServiceDiscovery<Service, Instance>(configuration: configuration)
        defer { serviceDiscovery.shutdown() }

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: unknownService)
        guard case .failure(let error) = result else {
            return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
        }
        guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
            return XCTFail("Expected LookupError.unknownService, got \(error)")
        }
    }

    private func ensureResult(serviceDiscovery: StaticServiceDiscovery<Service, Instance>, service: Service) throws -> Result<Set<Instance>, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Set<Instance>, Error>?

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
