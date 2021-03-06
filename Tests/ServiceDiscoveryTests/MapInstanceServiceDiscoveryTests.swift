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

        let fooResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: fooService)
        guard case .success(let _fooInstances) = fooResult else {
            return XCTFail("Failed to lookup instances for service[\(self.fooService)]")
        }
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.fooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, self.fooDerivedInstances, "Expected service[\(self.fooService)] to have instances \(self.fooDerivedInstances), got \(_fooInstances)")

        let barResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: barService)
        guard case .success(let _barInstances) = barResult else {
            return XCTFail("Failed to lookup instances for service[\(self.barService)]")
        }
        XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.barService)] to have 2 instances, got \(_barInstances.count)")
        XCTAssertEqual(_barInstances, self.barDerivedInstances, "Expected service[\(self.barService)] to have instances \(self.barDerivedInstances), got \(_barInstances)")
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { port in HostPort(host: "localhost", port: port) }

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: unknownService)
        guard case .failure(let error) = result else {
            return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
        }
        guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
            return XCTFail("Expected LookupError.unknownService, got \(error)")
        }
    }

    func test_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapInstance { port in HostPort(host: "localhost", port: port) }

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = SDAtomic<Int>(0)

        let onCompleteInvoked = SDAtomic<Bool>(false)
        let onComplete: (CompletionReason) -> Void = { reason in
            XCTAssertEqual(reason, .serviceDiscoveryUnavailable, "Expected CompletionReason to be .serviceDiscoveryUnavailable, got \(reason)")
            onCompleteInvoked.store(true)
        }

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        _ = serviceDiscovery.subscribe(
            to: self.barService,
            onNext: { result in
                resultCounter.add(1)

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
                    XCTAssertEqual(instances, self.barDerivedInstances, "Expected instances of \(self.barService) to be \(self.barDerivedInstances), got \(instances)")
                    semaphore.signal()
                }
            },
            onComplete: onComplete
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)
        baseServiceDiscovery.register(self.barService, instances: self.barBaseInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(), 2, "Expected to receive result 2 times, got \(resultCounter.load())")

        // Verify `onComplete` gets invoked on `shutdown`
        baseServiceDiscovery.shutdown()
        XCTAssertTrue(onCompleteInvoked.load(), "Expected onComplete to be invoked")
    }

    func test_subscribe_cancel() throws {
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapInstance { port in HostPort(host: "localhost", port: port) }

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter1 = SDAtomic<Int>(0)
        let resultCounter2 = SDAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscribers
        _ = serviceDiscovery.subscribe(
            to: self.barService,
            onNext: { result in
                resultCounter1.add(1)

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
                    XCTAssertEqual(instances, self.barDerivedInstances, "Expected instances of \(self.barService) to be \(self.barDerivedInstances), got \(instances)")
                    semaphore.signal()
                }
            },
            onComplete: { _ in }
        )

        let onCompleteInvoked = SDAtomic<Bool>(false)
        let onComplete: (CompletionReason) -> Void = { reason in
            XCTAssertEqual(reason, .cancellationRequested, "Expected CompletionReason to be .cancellationRequested, got \(reason)")
            onCompleteInvoked.store(true)
        }

        // This subscriber receives Result #1 only because we cancel subscription before Result #2 is triggered
        let cancellationToken = serviceDiscovery.subscribe(
            to: self.barService,
            onNext: { result in
                resultCounter2.add(1)

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
            },
            onComplete: onComplete
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)

        cancellationToken.cancel()
        // Only subscriber 1 will receive this change
        baseServiceDiscovery.register(self.barService, instances: self.barBaseInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter1.load(), 2, "Expected subscriber #1 to receive result 2 times, got \(resultCounter1.load())")
        XCTAssertEqual(resultCounter2.load(), 1, "Expected subscriber #2 to receive result 1 time, got \(resultCounter2.load())")
        // Verify `onComplete` gets invoked on `cancel`
        XCTAssertTrue(onCompleteInvoked.load(), "Expected onComplete to be invoked")
    }

    func test_concurrency() throws {
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let baseServiceDisovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDisovery.mapInstance { port in HostPort(host: "localhost", port: port) }

        let registerSemaphore = DispatchSemaphore(value: 0)
        let registerCounter = SDAtomic<Int>(0)

        let lookupSemaphore = DispatchSemaphore(value: 0)
        let lookupCounter = SDAtomic<Int>(0)

        let times = 100
        for _ in 1 ... times {
            DispatchQueue.global().async {
                baseServiceDisovery.register(self.fooService, instances: self.fooBaseInstances)
                registerCounter.add(1)

                if registerCounter.load() == times {
                    registerSemaphore.signal()
                }
            }

            DispatchQueue.global().async {
                serviceDiscovery.lookup(self.fooService, deadline: nil) { result in
                    lookupCounter.add(1)

                    guard case .success(let instances) = result, instances == self.fooDerivedInstances else {
                        return XCTFail("Failed to lookup instances for service[\(self.fooService)]: \(result)")
                    }

                    if lookupCounter.load() == times {
                        lookupSemaphore.signal()
                    }
                }
            }
        }

        _ = registerSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        _ = lookupSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        XCTAssertEqual(registerCounter.load(), times, "Expected register to succeed \(times) times")
        XCTAssertEqual(lookupCounter.load(), times, "Expected lookup callback to be called \(times) times")
    }

    func testThrownErrorsPropagateIntoFailures() throws {
        enum TestError: Error {
            case error
        }

        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooBaseInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { _ -> Int in throw TestError.error }

        let result = try self.ensureResult(serviceDiscovery: serviceDiscovery, service: self.fooService)
        guard case .failure(let err) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(err as? TestError, .error, "Expected \(TestError.error), but got \(err)")
    }

    func testPropagateDefaultTimeout() throws {
        let configuration = InMemoryServiceDiscovery<Service, BaseInstance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapInstance { port in HostPort(host: "localhost", port: port) }
        XCTAssertTrue(Self.compareTimeInterval(configuration.defaultLookupTimeout, serviceDiscovery.defaultLookupTimeout), "\(configuration.defaultLookupTimeout) does not match \(serviceDiscovery.defaultLookupTimeout)")
    }

    private func ensureResult<SD: ServiceDiscovery>(serviceDiscovery: SD, service: SD.Service) throws -> Result<[SD.Instance], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[SD.Instance], Error>?

        serviceDiscovery.lookup(service, deadline: nil) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        guard let _result = result else {
            throw LookupError.timedOut
        }

        return _result
    }

    private static func compareTimeInterval(_ lhs: DispatchTimeInterval, _ rhs: DispatchTimeInterval) -> Bool {
        switch (lhs, rhs) {
        case (.seconds(let lhs), .seconds(let rhs)):
            return lhs == rhs
        case (.milliseconds(let lhs), .milliseconds(let rhs)):
            return lhs == rhs
        case (.microseconds(let lhs), .microseconds(let rhs)):
            return lhs == rhs
        case (.nanoseconds(let lhs), .nanoseconds(let rhs)):
            return lhs == rhs
        case (.never, .never):
            return true
        case (.seconds, _), (.milliseconds, _), (.microseconds, _), (.nanoseconds, _), (.never, _):
            return false
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        @unknown default:
            return false
        #endif
        }
    }
}
