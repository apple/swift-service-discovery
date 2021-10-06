//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import ServiceDiscovery
import XCTest

enum TestError: Error {
    case error
}

func compareTimeInterval(_ lhs: DispatchTimeInterval, _ rhs: DispatchTimeInterval) -> Bool {
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

func ensureResult<SD: ServiceDiscovery>(serviceDiscovery: SD, service: SD.Service) throws -> Result<[SD.Instance], Error> {
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

#if compiler(>=5.5) && canImport(_Concurrency)
extension XCTestCase {
    // TODO: remove once XCTest supports async functions
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func runAsyncAndWaitFor(_ closure: @escaping @Sendable () async throws -> Void, _ timeout: TimeInterval = 1.0) {
        let finished = expectation(description: "finished")
        Task.detached {
            try await closure()
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}
#endif
