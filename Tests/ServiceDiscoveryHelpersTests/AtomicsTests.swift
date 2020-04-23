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

@testable import ServiceDiscoveryHelpers
import XCTest

class AtomicsTests: XCTestCase {
    func test_Bool() {
        let atomicBool = SDAtomic<Bool>(true)

        XCTAssertTrue(atomicBool.compareAndExchange(expected: true, desired: false))
        XCTAssertFalse(atomicBool.load())

        XCTAssertTrue(atomicBool.compareAndExchange(expected: false, desired: true))
        XCTAssertTrue(atomicBool.load())

        atomicBool.store(false)
        XCTAssertFalse(atomicBool.load())
    }

    func test_Int() {
        let atomicInt = SDAtomic<Int>(98)

        XCTAssertEqual(atomicInt.load(), 98)

        XCTAssertEqual(atomicInt.add(1), 98) // `add` returns value before the operation
        XCTAssertEqual(atomicInt.load(), 99)

        XCTAssertEqual(atomicInt.sub(2), 99) // `sub` returns value before the operation
        XCTAssertEqual(atomicInt.load(), 97)

        atomicInt.store(56)
        XCTAssertEqual(atomicInt.load(), 56)

        XCTAssertTrue(atomicInt.compareAndExchange(expected: 56, desired: 37))
        XCTAssertEqual(atomicInt.load(), 37)
    }
}
