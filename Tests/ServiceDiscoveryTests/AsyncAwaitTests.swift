//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the SwiftServiceDiscovery project authors
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
import ServiceDiscovery
import XCTest

final class MockServiceDiscovery: ServiceDiscovery {
    var defaultLookupTimeout: DispatchTimeInterval { .seconds(5) }

    typealias Service = String
    typealias Instance = String

    let cancelCounter = ManagedAtomic(0)

    init() {}

    func subscribe(
        to service: String,
        onNext nextResultHandler: @escaping (Result<[String], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void
    ) -> CancellationToken { CancellationToken { _ in self.cancelCounter.wrappingIncrement(ordering: .relaxed) } }

    func lookup(_ service: String, deadline: DispatchTime?, callback: @escaping (Result<[String], Error>) -> Void) {
        fatalError("TODO: Unimplemented")
    }
}

final class AsyncAwaitTests: XCTestCase {
    func testCancellationTokenIsInvoked() async throws {
        let discoveryService = MockServiceDiscovery()

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            let snapshots = discoveryService.subscribe(to: "foo")

            taskGroup.addTask { for try await _ in snapshots { XCTFail("Should never be reached") } }

            XCTAssertEqual(discoveryService.cancelCounter.load(ordering: .relaxed), 0)
            taskGroup.cancelAll()
            _ = await taskGroup.nextResult()

            // Wait for task group to be cancelled and cancelCounter is incremented
            repeat { try await Task.sleep(nanoseconds: 10_000_000) } while !taskGroup.isCancelled

            XCTAssertEqual(discoveryService.cancelCounter.load(ordering: .relaxed), 1)
        }
    }
}
