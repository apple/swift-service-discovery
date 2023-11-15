# ``ServiceDiscovery``

A Service Discovery API for Swift.

## Overview

Service discovery is how services locate one another within a distributed system. This API library is designed to establish a standard that can be implemented by various service discovery backends such as DNS-based, key-value store like Zookeeper, etc. In other words, this library defines the API only, similar to [SwiftLog](https://github.com/apple/swift-log) and [SwiftMetrics](https://github.com/apple/swift-metrics); actual functionalities are provided by backend implementations.

## Getting started

If you have a server-side Swift application and would like to locate other services within the same system for making HTTP requests or RPCs, then ServiceDiscovery is the right library for the job. Below you will find all you need to know to get started.

A service may have zero or more instances, each of which has an associated location (for example host-port). `Instance` denotes the service instance type used in a backend implementation.

## Selecting a service discovery backend implementation (applications only)

> Note: If you are building a library, you don't need to concern yourself with this section. It is the end users of your library (the applications) who will decide which service discovery backend to use. Libraries should never change the service discovery implementation as that is something owned by the application.

ServiceDiscovery only provides the service discovery API. As an application owner, you need to select a service discovery backend to make querying available.

Selecting a backend is done by adding a dependency on the desired backend implementation and instantiating it at the beginning of the program.

For example, suppose you have chosen the hypothetical `DNSBasedServiceDiscovery` as the backend:

```swift
// 1) Import the service discovery backend package
import DNSBasedServiceDiscovery

// 2) Create a concrete ServiceDiscovery object
let serviceDiscovery = DNSBasedServiceDiscovery()
```

As the API has just launched, not many implementations exist yet. If you are interested in implementing one see the "Implementing a service discovery backend" section below explaining how to do so. List of existing ServiceDiscovery API compatible libraries:

- [tuplestream/swift-k8s-service-discovery](https://github.com/tuplestream/swift-k8s-service-discovery) - service discovery using the k8s APIs

### Obtaining a service's instances

To fetch the current list of instances:

```swift
let instances: [Instance] = try await serviceDiscovery.lookup()
```
   
To fetch the current list of instances **AND** subscribe to future changes:

```swift
for try await instances in serviceDiscovery.subscribe() {
    // do something with this snapshot of instances
}
```

Underlying the async `subscribe` API is an `AsyncSequence`. To end the subscription, simply break out of the `for`-loop.

Note the `AsyncSequence` is of a `Result` type, wrapping either the instances discovered, or a discovery error if such occurred.
A client should decide how to best handle errors in this case, e.g. terminate the subscription or continue and handle the errors.

## Implementing a service discovery backend

> Note: Unless you need to implement a custom service discovery backend, everything in this section is likely not relevant, so please feel free to skip.

### Adding the dependency

To add a dependency on the API package, you need to declare it in your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-service-discovery.git", from: "2.0.0"),
```

and to your library target, add `ServiceDiscovery` to your dependencies:

```swift
.target(
    name: "MyServiceDiscovery",
    dependencies: [
        .product(name: "ServiceDiscovery", package: "swift-service-discovery"),
    ]
),
```

To become a compatible service discovery backend that all ServiceDiscovery consumers can use, you need to implement a type that conforms to the ``ServiceDiscovery/ServiceDiscovery`` protocol provided by ServiceDiscovery. It includes two methods, ``ServiceDiscovery/lookup`` and ``ServiceDiscovery/subscribe``.

#### lookup

```swift
/// Performs async lookup for the given service's instances.
///
/// - Returns: A listing of service discovery instances.
/// - throws when failing to lookup instances
func lookup() async throws -> [Instance]
```

`lookup` fetches the current list of instances asynchronously.

#### subscribe

```swift
/// Subscribes to receive service discovery change notification whenever service discovery instances change.
///
/// - Returns a ``ServiceDiscoverySubscription`` which produces an `AsyncSequence` of changes in  the service discovery instances.
/// - throws when failing to establish subscription
func subscribe() async throws -> DiscoverySequence
```

`subscribe` returns an ``AsyncSequence`` that yields a Result type containing array of instances or error information. 
The set of instances is the complete set of known instances at yield time. The backend should yield:

- When `subscribe` is first invoked, the caller should receive the current list of instances for the given service. This is essentially the `lookup` result.
- Whenever the given service's list of instances changes. The backend implementation has full control over how and when its service records get updated, but it must yield when the instances list becomes different from the previous result.


## Topics

### Service Discovery API

- ``ServiceDiscovery/lookup()``
- ``ServiceDiscovery/subscribe()``

