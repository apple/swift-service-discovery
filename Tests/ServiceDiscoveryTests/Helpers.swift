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
