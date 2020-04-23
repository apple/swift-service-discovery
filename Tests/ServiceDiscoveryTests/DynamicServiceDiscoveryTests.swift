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

class DynamicServiceDiscoveryTests: XCTestCase {
    func test_subscribe() {
        let serviceDiscovery = MockDynamicServiceDiscovery()
        defer { serviceDiscovery.shutdown() }

        let semaphore = DispatchSemaphore(value: 0)
        let counterA = SDAtomic<Int>(0)
        let counterB = SDAtomic<Int>(0)

        serviceDiscovery.subscribe(service: "test-service", refreshInterval: .milliseconds(100)) { instances in
            let counter = serviceDiscovery.counter

            switch instances {
            case serviceDiscovery.instancesA:
                XCTAssertTrue(counter == 1 || counter == 4, "Expected to receive instancesA at counter 1 and 4 only, got it at \(counter)")
                _ = counterA.add(1)
            case serviceDiscovery.instancesB:
                XCTAssertTrue(counter == 3, "Expected to receive instancesB at counter 3 only, got it at \(counter)")
                _ = counterB.add(1)
            default:
                return XCTFail("Unexpected instances: \(instances)")
            }

            if counter >= 4 {
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: DispatchTime.now() + .seconds(1))

        // A (counter=1), B -> A (4)
        XCTAssertEqual(counterA.load(), 2, "Expected to receive instancesA 2 times, got \(counterA)")
        // A -> B (3)
        XCTAssertEqual(counterB.load(), 1, "Expected to receive instancesB 1 time, got \(counterB)")
    }
}

private class MockDynamicServiceDiscovery: DynamicServiceDiscovery {
    typealias Service = String
    typealias Instance = HostPort

    let defaultLookupTimeout: DispatchTimeInterval = .milliseconds(50)
    let defaultRefreshInterval: DispatchTimeInterval = .milliseconds(50)
    let instancesToExclude: Set<HostPort>? = nil

    private let _isShutdown = SDAtomic<Bool>(false)

    public var isShutdown: Bool {
        self._isShutdown.load()
    }

    let instancesA: Set<Instance> = [
        HostPort(host: "localhost", port: 7001),
    ]
    let instancesB: Set<Instance> = [
        HostPort(host: "localhost", port: 9001),
        HostPort(host: "localhost", port: 9002),
    ]

    var counter: Int = 0

    func lookup(service: Service, deadline: DispatchTime?, callback: @escaping (Result<Set<Instance>, Error>) -> Void) {
        self.counter += 1

        if self.counter % 3 == 0 {
            callback(.success(self.instancesB))
        } else {
            callback(.success(self.instancesA))
        }
    }

    func shutdown() {
        self._isShutdown.store(true)
    }
}
