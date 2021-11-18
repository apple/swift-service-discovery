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

class MapServiceServiceDiscoveryTests: XCTestCase {
    typealias ComputedService = Int
    typealias Service = String
    typealias Instance = HostPort

    let services = ["fooService", "bar-service"]

    let computedFooService = 0
    let fooService = "fooService"
    let fooInstances = [
        HostPort(host: "localhost", port: 7001),
    ]

    let computedBarService = 1
    let barService = "bar-service"
    let barInstances = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    func test_lookup() throws {
        var configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        configuration.register(service: self.barService, instances: self.barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService { (service: Int) in self.services[service] }

        let fooResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: computedFooService)
        guard case .success(let _fooInstances) = fooResult else {
            return XCTFail("Failed to lookup instances for service[\(self.computedFooService)]")
        }
        XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.computedFooService)] to have 1 instance, got \(_fooInstances.count)")
        XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.computedFooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

        let barResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: computedBarService)
        guard case .success(let _barInstances) = barResult else {
            return XCTFail("Failed to lookup instances for service[\(self.computedBarService)]")
        }
        XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.computedBarService)] to have 2 instances, got \(_barInstances.count)")
        XCTAssertEqual(_barInstances, self.barInstances, "Expected service[\(self.computedBarService)] to have instances \(self.barInstances), got \(_barInstances)")
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"
        let unknownComputedService = 3

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService(serviceType: Int.self) { _ in unknownService }

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: unknownComputedService)
        guard case .failure(let error) = result else {
            return XCTFail("Lookup instances for service[\(unknownComputedService)] should return an error")
        }
        guard let lookupError = error as? LookupError, case .unknownService = lookupError else {
            return XCTFail("Expected LookupError.unknownService, got \(error)")
        }
    }

    func test_subscribe() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapService(serviceType: Int.self) { service in self.services[service] }

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = ManagedAtomic<Int>(0)

        let onCompleteInvoked = ManagedAtomic<Bool>(false)
        let onComplete: (CompletionReason) -> Void = { reason in
            XCTAssertEqual(reason, .serviceDiscoveryUnavailable, "Expected CompletionReason to be .serviceDiscoveryUnavailable, got \(reason)")
            onCompleteInvoked.store(true, ordering: .relaxed)
        }

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        _ = serviceDiscovery.subscribe(
            to: self.computedBarService,
            onNext: { result in
                resultCounter.wrappingIncrement(ordering: .relaxed)

                guard resultCounter.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                        return XCTFail("Expected the first result to be LookupError.unknownService since \(self.computedBarService) is not registered, got \(error)")
                    }
                case .success(let instances):
                    guard resultCounter.load(ordering: .relaxed) == 2 else {
                        return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter.load(ordering: .relaxed)) got \(instances)")
                    }
                    XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.computedBarService) to be \(self.barInstances), got \(instances)")
                    semaphore.signal()
                }
            },
            onComplete: onComplete
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)
        baseServiceDiscovery.register(self.barService, instances: self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter.load(ordering: .relaxed), 2, "Expected to receive result 2 times, got \(resultCounter.load(ordering: .relaxed))")

        // Verify `onComplete` gets invoked on `shutdown`
        baseServiceDiscovery.shutdown()
        XCTAssertTrue(onCompleteInvoked.load(ordering: .relaxed), "Expected onComplete to be invoked")
    }

    func test_subscribe_cancel() throws {
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapService(serviceType: Int.self) { service in self.services[service] }

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter1 = ManagedAtomic<Int>(0)
        let resultCounter2 = ManagedAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscribers
        _ = serviceDiscovery.subscribe(
            to: self.computedBarService,
            onNext: { result in
                resultCounter1.wrappingIncrement(ordering: .relaxed)

                guard resultCounter1.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter1.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                        return XCTFail("Expected the first result to be LookupError.unknownService since \(self.computedBarService) is not registered, got \(error)")
                    }
                case .success(let instances):
                    guard resultCounter1.load(ordering: .relaxed) == 2 else {
                        return XCTFail("Expected to receive instances list on the second result only, but at result #\(resultCounter1.load(ordering: .relaxed)) got \(instances)")
                    }
                    XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.computedBarService) to be \(self.barInstances), got \(instances)")
                    semaphore.signal()
                }
            },
            onComplete: { _ in }
        )

        let onCompleteInvoked = ManagedAtomic<Bool>(false)
        let onComplete: (CompletionReason) -> Void = { reason in
            XCTAssertEqual(reason, .cancellationRequested, "Expected CompletionReason to be .cancellationRequested, got \(reason)")
            onCompleteInvoked.store(true, ordering: .relaxed)
        }

        // This subscriber receives Result #1 only because we cancel subscription before Result #2 is triggered
        let cancellationToken = serviceDiscovery.subscribe(
            to: self.computedBarService,
            onNext: { result in
                resultCounter2.wrappingIncrement(ordering: .relaxed)

                guard resultCounter2.load(ordering: .relaxed) <= 1 else {
                    return XCTFail("Expected to receive result 1 time only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter2.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError, case .unknownService = lookupError else {
                        return XCTFail("Expected the first result to be LookupError.unknownService since \(self.computedBarService) is not registered, got \(error)")
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
        baseServiceDiscovery.register(self.barService, instances: self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(resultCounter1.load(ordering: .relaxed), 2, "Expected subscriber #1 to receive result 2 times, got \(resultCounter1.load(ordering: .relaxed))")
        XCTAssertEqual(resultCounter2.load(ordering: .relaxed), 1, "Expected subscriber #2 to receive result 1 time, got \(resultCounter2.load(ordering: .relaxed))")
        // Verify `onComplete` gets invoked on `cancel`
        XCTAssertTrue(onCompleteInvoked.load(ordering: .relaxed), "Expected onComplete to be invoked")
    }

    func test_concurrency() throws {
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        let baseServiceDisovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDisovery.mapService(serviceType: Int.self) { service in self.services[service] }

        let registerSemaphore = DispatchSemaphore(value: 0)
        let registerCounter = ManagedAtomic<Int>(0)

        let lookupSemaphore = DispatchSemaphore(value: 0)
        let lookupCounter = ManagedAtomic<Int>(0)

        let times = 100
        for _ in 1 ... times {
            DispatchQueue.global().async {
                baseServiceDisovery.register(self.fooService, instances: self.fooInstances)
                registerCounter.wrappingIncrement(ordering: .relaxed)

                if registerCounter.load(ordering: .relaxed) == times {
                    registerSemaphore.signal()
                }
            }

            DispatchQueue.global().async {
                serviceDiscovery.lookup(self.computedFooService, deadline: nil) { result in
                    lookupCounter.wrappingIncrement(ordering: .relaxed)

                    guard case .success(let instances) = result, instances == self.fooInstances else {
                        return XCTFail("Failed to lookup instances for service[\(self.fooService)]: \(result)")
                    }

                    if lookupCounter.load(ordering: .relaxed) == times {
                        lookupSemaphore.signal()
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
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService { (_: Int) -> String in throw TestError.error }

        let result = try ensureResult(serviceDiscovery: serviceDiscovery, service: self.computedFooService)
        guard case .failure(let err) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(err as? TestError, .error, "Expected \(TestError.error), but got \(err)")
    }

    func testThrownErrorsPropagateIntoCancelledSubscriptions() throws {
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService { (_: Int) -> String in throw TestError.error }

        let resultGroup = DispatchGroup()
        resultGroup.enter()
        resultGroup.enter()

        let token = serviceDiscovery.subscribe(
            to: self.computedFooService,
            onNext: { result in
                defer {
                    resultGroup.leave()
                }
                guard case .failure(let err) = result else {
                    XCTFail("Expected error, got \(result)")
                    return
                }
                XCTAssertEqual(err as? TestError, .error)
            },
            onComplete: { reason in
                defer {
                    resultGroup.leave()
                }
                XCTAssertEqual(reason, .failedToMapService)
            }
        )
        XCTAssertTrue(token.isCancelled)
    }

    func testPropagateDefaultTimeout() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService(serviceType: Int.self) { service in self.services[service] }
        XCTAssertTrue(compareTimeInterval(configuration.defaultLookupTimeout, serviceDiscovery.defaultLookupTimeout), "\(configuration.defaultLookupTimeout) does not match \(serviceDiscovery.defaultLookupTimeout)")
    }

    // MARK: - async/await API tests

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func test_async_lookup() throws {
        #if !(compiler(>=5.5) && canImport(_Concurrency))
        try XCTSkipIf(true)
        #else
        var configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        configuration.register(service: self.barService, instances: self.barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService { (service: Int) in self.services[service] }

        runAsyncAndWaitFor {
            let _fooInstances = try await serviceDiscovery.lookup(self.computedFooService)
            XCTAssertEqual(_fooInstances.count, 1, "Expected service[\(self.computedFooService)] to have 1 instance, got \(_fooInstances.count)")
            XCTAssertEqual(_fooInstances, self.fooInstances, "Expected service[\(self.computedFooService)] to have instances \(self.fooInstances), got \(_fooInstances)")

            let _barInstances = try await serviceDiscovery.lookup(self.computedBarService)
            XCTAssertEqual(_barInstances.count, 2, "Expected service[\(self.computedBarService)] to have 2 instances, got \(_barInstances.count)")
            XCTAssertEqual(_barInstances, self.barInstances, "Expected service[\(self.computedBarService)] to have instances \(self.barInstances), got \(_barInstances)")
        }
        #endif
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func test_async_lookup_errorIfServiceUnknown() throws {
        #if !(compiler(>=5.5) && canImport(_Concurrency))
        try XCTSkipIf(true)
        #else
        let unknownService = "unknown-service"
        let unknownComputedService = 3

        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService(serviceType: Int.self) { _ in unknownService }

        runAsyncAndWaitFor {
            do {
                _ = try await serviceDiscovery.lookup(unknownComputedService)
                return XCTFail("Lookup instances for service[\(unknownComputedService)] should return an error")
            } catch {
                guard let lookupError = error as? LookupError, lookupError == .unknownService else {
                    return XCTFail("Expected LookupError.unknownService, got \(error)")
                }
            }
        }
        #endif
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func test_async_subscribe() throws {
        #if !(compiler(>=5.5) && canImport(_Concurrency))
        try XCTSkipIf(true)
        #else
        let configuration = InMemoryServiceDiscovery<Service, Instance>.Configuration(serviceInstances: [fooService: self.fooInstances])
        let baseServiceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
        let serviceDiscovery = baseServiceDiscovery.mapService(serviceType: Int.self) { service in self.services[service] }

        let semaphore = DispatchSemaphore(value: 0)
        let counter = ManagedAtomic<Int>(0)

        Task.detached {
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            baseServiceDiscovery.register(self.barService, instances: [])
            usleep(50000)
            // Update #2
            baseServiceDiscovery.register(self.barService, instances: self.barInstances)
        }

        let task = Task.detached { () -> Void in
            do {
                for try await instances in serviceDiscovery.subscribe(to: self.computedBarService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(instances, [], "Expected instances of \(self.computedBarService) to be empty, got \(instances)")
                    case 2:
                        XCTAssertEqual(instances, self.barInstances, "Expected instances of \(self.computedBarService) to be \(self.barInstances), got \(instances)")
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
        #endif
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testThrownErrorsPropagateIntoAsyncSubscriptions() throws {
        #if !(compiler(>=5.5) && canImport(_Concurrency))
        try XCTSkipIf(true)
        #else
        let configuration = InMemoryServiceDiscovery.Configuration(serviceInstances: [fooService: self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration).mapService { (_: Int) -> String in throw TestError.error }

        let semaphore = DispatchSemaphore(value: 0)

        let task = Task.detached { () -> Void in
            do {
                for try await instances in serviceDiscovery.subscribe(to: self.computedFooService) {
                    XCTFail("Expected error, got \(instances)")
                }
            } catch {
                guard let err = error as? TestError, err == .error else {
                    return XCTFail("Expected TestError.error, got \(error)")
                }
            }
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        task.cancel()
        #endif
    }
}
