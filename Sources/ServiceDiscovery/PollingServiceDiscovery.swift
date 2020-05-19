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

/// Polls for service instance updates at fixed interval.
public protocol PollingServiceDiscovery: ServiceDiscovery, AnyObject {
    /// The frequency at which `subscribe` will poll for updates.
    var pollInterval: DispatchTimeInterval { get }

    /// Performs a lookup for the given service's instances. The result will be sent to `callback`.
    ///
    /// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
    ///
    /// - Note: This method is the same as `ServiceDiscovery.lookup` except this is non-mutating. It is a workaround
    ///         for [SR-142](https://bugs.swift.org/browse/SR-142) and allows the library to provide default
    ///         implementation for `subscribe` in the extension.
    func lookup(_ service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)
}

extension PollingServiceDiscovery {
    public func subscribe(to service: Service, handler: @escaping (Result<[Instance], Error>) -> Void) {
        self.lookup(service, deadline: nil) { result in
            handler(result)

            switch result {
            case .success(let instances):
                self._pollAndNotifyOnChange(service: service, previousInstances: instances, onChange: handler)
            case .failure:
                self._pollAndNotifyOnChange(service: service, previousInstances: nil, onChange: handler)
            }
        }
    }

    private func _pollAndNotifyOnChange(service: Service, previousInstances: [Instance]?, onChange: @escaping (Result<[Instance], Error>) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + self.pollInterval) {
            guard !self.isShutdown else { return }

            self.lookup(service, deadline: nil) { result in
                // Subsequent lookups should only notify if instances have changed
                switch result {
                case .success(let instances):
                    if previousInstances != instances {
                        onChange(.success(instances))
                    }
                    self._pollAndNotifyOnChange(service: service, previousInstances: instances, onChange: onChange)
                case .failure:
                    self._pollAndNotifyOnChange(service: service, previousInstances: previousInstances, onChange: onChange)
                }
            }
        }
    }
}
