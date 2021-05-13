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

@testable import ServiceDiscovery
import XCTest

extension XCTestCase {
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
}

#if compiler(>=5.5)
extension XCTestCase {
    // TODO: remove once XCTest supports async functions
    @available(macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, *)
    func runAsyncAndWaitFor(_ closure: @escaping () async -> Void, _ timeout: TimeInterval = 1.0) {
        let finished = expectation(description: "finished")
        detach {
            await closure()
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}
#endif
