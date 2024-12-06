//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2024 Apple Inc. and the SwiftServiceDiscovery project authors
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

    static let fooService = "fooService"
    static let fooInstances = [HostPort(host: "localhost", port: 7001)]

    static let barService = "bar-service"
    static let barInstances = [HostPort(host: "localhost", port: 9001), HostPort(host: "localhost", port: 9002)]

    func test_lookup() throws {
        var configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        configuration.register(service: Self.barService, instances: Self.barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let fooResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: Self.fooService)
        guard case .success(let _fooInstances) = fooResult else {
            return XCTFail("Failed to lookup instances for service[\(Self.fooService)]")
        }
        XCTAssertEqual(
            _fooInstances.count,
            1,
            "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)"
        )
        XCTAssertEqual(
            _fooInstances,
            Self.fooInstances,
            "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)"
        )

        let barResult = try ensureResult(serviceDiscovery: serviceDiscovery, service: Self.barService)
        guard case .success(let _barInstances) = barResult else {
            return XCTFail("Failed to lookup instances for service[\(Self.barService)]")
        }
        XCTAssertEqual(
            _barInstances.count,
            2,
            "Expected service[\(Self.barService)] to have 2 instances, got \(_barInstances.count)"
        )
        XCTAssertEqual(
            _barInstances,
            Self.barInstances,
            "Expected service[\(Self.barService)] to have instances \(Self.barInstances), got \(_barInstances)"
        )
    }

    func test_lookup_errorIfServiceUnknown() throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: ["foo-service": []])
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
        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter = ManagedAtomic<Int>(0)

        let onCompleteInvoked = ManagedAtomic<Bool>(false)
        let onComplete: @Sendable (CompletionReason) -> Void = { reason in
            XCTAssertEqual(
                reason,
                .serviceDiscoveryUnavailable,
                "Expected CompletionReason to be .serviceDiscoveryUnavailable, got \(reason)"
            )
            onCompleteInvoked.store(true, ordering: .relaxed)
        }

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscriber
        serviceDiscovery.subscribe(
            to: Self.barService,
            onNext: { result in
                resultCounter.wrappingIncrement(ordering: .relaxed)

                guard resultCounter.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError,
                        case .unknownService = lookupError
                    else {
                        return XCTFail(
                            "Expected the first result to be LookupError.unknownService since \(Self.barService) is not registered, got \(error)"
                        )
                    }
                case .success(let instances):
                    guard resultCounter.load(ordering: .relaxed) == 2 else {
                        return XCTFail(
                            "Expected to receive instances list on the second result only, but at result #\(resultCounter.load(ordering: .relaxed)) got \(instances)"
                        )
                    }
                    XCTAssertEqual(
                        instances,
                        Self.barInstances,
                        "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)"
                    )
                    semaphore.signal()
                }
            },
            onComplete: onComplete
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)
        serviceDiscovery.register(Self.barService, instances: Self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(
            resultCounter.load(ordering: .relaxed),
            2,
            "Expected to receive result 2 times, got \(resultCounter.load(ordering: .relaxed))"
        )

        // Verify `onComplete` gets invoked on `shutdown`
        serviceDiscovery.shutdown()
        XCTAssertTrue(onCompleteInvoked.load(ordering: .relaxed), "Expected onComplete to be invoked")
    }

    func test_subscribe_cancel() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        let resultCounter1 = ManagedAtomic<Int>(0)
        let resultCounter2 = ManagedAtomic<Int>(0)

        // Two results are expected:
        // Result #1: LookupError.unknownService because bar-service is not registered
        // Result #2: Later we register bar-service and that should notify the subscribers
        serviceDiscovery.subscribe(
            to: Self.barService,
            onNext: { result in
                resultCounter1.wrappingIncrement(ordering: .relaxed)

                guard resultCounter1.load(ordering: .relaxed) <= 2 else {
                    return XCTFail("Expected to receive result 2 times only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter1.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError,
                        case .unknownService = lookupError
                    else {
                        return XCTFail(
                            "Expected the first result to be LookupError.unknownService since \(Self.barService) is not registered, got \(error)"
                        )
                    }
                case .success(let instances):
                    guard resultCounter1.load(ordering: .relaxed) == 2 else {
                        return XCTFail(
                            "Expected to receive instances list on the second result only, but at result #\(resultCounter1.load(ordering: .relaxed)) got \(instances)"
                        )
                    }
                    XCTAssertEqual(
                        instances,
                        Self.barInstances,
                        "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)"
                    )
                    semaphore.signal()
                }
            }
        )

        let onCompleteInvoked = ManagedAtomic<Bool>(false)
        let onComplete: @Sendable (CompletionReason) -> Void = { reason in
            XCTAssertEqual(
                reason,
                .cancellationRequested,
                "Expected CompletionReason to be .cancellationRequested, got \(reason)"
            )
            onCompleteInvoked.store(true, ordering: .relaxed)
        }

        // This subscriber receives Result #1 only because we cancel subscription before Result #2 is triggered
        let cancellationToken = serviceDiscovery.subscribe(
            to: Self.barService,
            onNext: { result in
                resultCounter2.wrappingIncrement(ordering: .relaxed)

                guard resultCounter2.load(ordering: .relaxed) <= 1 else {
                    return XCTFail("Expected to receive result 1 time only")
                }

                switch result {
                case .failure(let error):
                    guard resultCounter2.load(ordering: .relaxed) == 1, let lookupError = error as? LookupError,
                        case .unknownService = lookupError
                    else {
                        return XCTFail(
                            "Expected the first result to be LookupError.unknownService since \(Self.barService) is not registered, got \(error)"
                        )
                    }
                case .success: return XCTFail("Does not expect to receive instances list")
                }
            },
            onComplete: onComplete
        )

        // Allow time for first result of `subscribe`
        usleep(100_000)

        cancellationToken.cancel()
        // Only subscriber 1 will receive this change
        serviceDiscovery.register(Self.barService, instances: Self.barInstances)

        _ = semaphore.wait(timeout: DispatchTime.now() + .milliseconds(200))

        XCTAssertEqual(
            resultCounter1.load(ordering: .relaxed),
            2,
            "Expected subscriber #1 to receive result 2 times, got \(resultCounter1.load(ordering: .relaxed))"
        )
        XCTAssertEqual(
            resultCounter2.load(ordering: .relaxed),
            1,
            "Expected subscriber #2 to receive result 1 time, got \(resultCounter2.load(ordering: .relaxed))"
        )
        // Verify `onComplete` gets invoked on `cancel`
        XCTAssertTrue(onCompleteInvoked.load(ordering: .relaxed), "Expected onComplete to be invoked")
    }

    func test_concurrency() throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let registerSemaphore = DispatchSemaphore(value: 0)
        let registerCounter = ManagedAtomic<Int>(0)

        let lookupSemaphore = DispatchSemaphore(value: 0)
        let lookupCounter = ManagedAtomic<Int>(0)

        let times = 100
        for _ in 1...times {
            DispatchQueue.global()
                .async {
                    serviceDiscovery.register(Self.fooService, instances: Self.fooInstances)
                    registerCounter.wrappingIncrement(ordering: .relaxed)

                    if registerCounter.load(ordering: .relaxed) == times { registerSemaphore.signal() }
                }

            DispatchQueue.global()
                .async {
                    serviceDiscovery.lookup(Self.fooService) { result in
                        lookupCounter.wrappingIncrement(ordering: .relaxed)

                        guard case .success(let instances) = result, instances == Self.fooInstances else {
                            return XCTFail("Failed to lookup instances for service[\(Self.fooService)]: \(result)")
                        }

                        if lookupCounter.load(ordering: .relaxed) == times { lookupSemaphore.signal() }
                    }
                }
        }

        _ = registerSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))
        _ = lookupSemaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        XCTAssertEqual(registerCounter.load(ordering: .relaxed), times, "Expected register to succeed \(times) times")
        XCTAssertEqual(
            lookupCounter.load(ordering: .relaxed),
            times,
            "Expected lookup callback to be called \(times) times"
        )
    }

    // MARK: - async/await API tests

    func test_async_lookup() async throws {
        var configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        configuration.register(service: Self.barService, instances: Self.barInstances)

        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let _fooInstances = try await serviceDiscovery.lookup(Self.fooService)
        XCTAssertEqual(
            _fooInstances.count,
            1,
            "Expected service[\(Self.fooService)] to have 1 instance, got \(_fooInstances.count)"
        )
        XCTAssertEqual(
            _fooInstances,
            Self.fooInstances,
            "Expected service[\(Self.fooService)] to have instances \(Self.fooInstances), got \(_fooInstances)"
        )

        let _barInstances = try await serviceDiscovery.lookup(Self.barService)
        XCTAssertEqual(
            _barInstances.count,
            2,
            "Expected service[\(Self.barService)] to have 2 instances, got \(_barInstances.count)"
        )
        XCTAssertEqual(
            _barInstances,
            Self.barInstances,
            "Expected service[\(Self.barService)] to have instances \(Self.barInstances), got \(_barInstances)"
        )
    }

    func test_async_lookup_errorIfServiceUnknown() async throws {
        let unknownService = "unknown-service"

        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: ["foo-service": []])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        do {
            _ = try await serviceDiscovery.lookup(unknownService)
            return XCTFail("Lookup instances for service[\(unknownService)] should return an error")
        } catch {
            guard let lookupError = error as? LookupError, lookupError == .unknownService else {
                return XCTFail("Expected LookupError.unknownService, got \(error)")
            }
        }
    }

    func test_async_subscribe() async throws {
        let configuration = InMemoryServiceDiscovery<Service, Instance>
            .Configuration(serviceInstances: [Self.fooService: Self.fooInstances])
        let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)

        let counter = ManagedAtomic<Int>(0)

        Task { @Sendable in
            // Allow time for subscription to start
            usleep(100_000)
            // Update #1
            serviceDiscovery.register(Self.barService, instances: [])
            usleep(50000)
            // Update #2
            serviceDiscovery.register(Self.barService, instances: Self.barInstances)
        }

        let task = Task<Void, Error> { @Sendable in
            do {
                for try await instances in serviceDiscovery.subscribe(to: Self.barService) {
                    switch counter.wrappingIncrementThenLoad(ordering: .relaxed) {
                    case 1:
                        XCTAssertEqual(
                            instances,
                            [],
                            "Expected instances of \(Self.barService) to be empty, got \(instances)"
                        )
                    case 2:
                        XCTAssertEqual(
                            instances,
                            Self.barInstances,
                            "Expected instances of \(Self.barService) to be \(Self.barInstances), got \(instances)"
                        )
                        // This causes the stream to terminate
                        serviceDiscovery.shutdown()
                    default: XCTFail("Expected to receive instances 2 times")
                    }
                }
            } catch {
                switch counter.load(ordering: .relaxed) {
                case 2:  // shutdown is called after receiving two results
                    guard let serviceDiscoveryError = error as? ServiceDiscoveryError,
                        serviceDiscoveryError == .unavailable
                    else { return XCTFail("Expected ServiceDiscoveryError.unavailable, got \(error)") }
                // Test is complete at this point
                default: XCTFail("Unexpected error \(error)")
                }
            }
        }

        _ = await task.result

        XCTAssertEqual(
            counter.load(ordering: .relaxed),
            2,
            "Expected to receive instances 2 times, got \(counter.load(ordering: .relaxed)) times"
        )
    }
}
