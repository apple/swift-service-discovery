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

        let fooResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: fooService)
        guard case .success(let _fooInstances) = fooResult else {
            return XCTFail("Failed to lookup instances for service[\(self.fooService)]")
        }
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.fooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

        let barResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: barService)
        guard case .success(let _barInstances) = barResult else {
            return XCTFail("Failed to lookup instances for service[\(self.barService)]")
        }
        XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.barService)] to have 2 instances, got \(_barInstances.count)")
        XCTAssertEqual(_barInstances, self.barInstances, "Expected service[\(self.barService)] to have instances \(self.barInstances), got \(_barInstances)")
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery<Service, Instance>(configuration: configuration)

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: unknownService)
        guard case .failure(let error) = result else {
            return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
        }
        guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
            return XCTFail("Expected LookupError.unknownService, got \(error)")
        }
    }

    func test_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = SDAtomic<Int>(0)

        let onTerminateInvoked = SDAtomic<Bool>(false)
        let onTerminate: () -> Void = { onTerminateInvoked.store(true) }

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        _ = serviceDiscovery.subscribe(to: self.barService, onTerminate: onTerminate) { result in
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

        // Verify `onTerminate` gets invoked on `shutdown`
        serviceDiscovery.shutdown()
        XCTAssertTrue(onTerminateInvoked.load(), "Expected onTerminate to be invoked")
    }

    func test_subscribe_cancel() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter1 = SDAtomic<Int>(0)
        let resultCounter2 = SDAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscribers
        _ = serviceDiscovery.subscribe(to: self.barService, onTerminate: {}) { result in
            _ = resultCounter1.add(1)

            guard resultCounter1.load() <= 2 else {
                return XCTFail("Expected to receive result 2 times only")
            }

            switch result {
            case .failure(let error):
                guard resultCounter1.load() == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                    return XCTFail("Expected the first result to be LookupError.unknownService since \(self.barService) is not registered, got \(error)")
                }
            case .success(let instances):
                guard resultCounter1.load() == 2 else {
                    return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter1.load()) got \(instances)")
                }
                XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.barService) to be \(self.barInstances), got \(instances)")
                semaphore.signal()
            }
        }

        // This subscriber receives Result #1 only because we cancel subscription before Result #2 is triggered
        let token = serviceDiscovery.subscribe(to: self.barService, onTerminate: {}) { result in
            _ = resultCounter2.add(1)

            guard resultCounter2.load() <= 1 else {
                return XCTFail("Expected to receive result 1 time only")
            }

            switch result {
            case .failure(let error):
                guard resultCounter2.load() == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                    return XCTFail("Expected the first result to be LookupError.unknownService since \(self.barService) is not registered, got \(error)")
                }
            case .success:
                return XCTFail("Does not expect to receive instances list")
            }
        }

        token.cancel()
        // Only subscriber 1 will receive this change
        serviceDiscovery.register(self.barService, instances: self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter1.load(), 2, "Expected subscriber #1 to receive result 2 times, got \(resultCounter1.load())")
        XCTAssertEqual(resultCounter2.load(), 1, "Expected subscriber #2 to receive result 1 time, got \(resultCounter2.load())")
    }

    private func ensureResult(serviceDiscovery: InMemoryServiceDiscovery<Service, Instance>, service: Service) throws -> Result<[Instance], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[Instance], Error>?

        serviceDiscovery.lookup(service) {
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
