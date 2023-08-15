# ``ServiceDiscovery``

A Service Discovery API for Swift.
                                
## Overview

Service discovery is how services locate one another within a distributed system. This API library is designed to establish a standard that can be implemented by various service discovery backends such as DNS-based, key-value store like Zookeeper, etc. In other words, this library defines the API only, similar to [SwiftLog](https://github.com/apple/swift-log) and [SwiftMetrics](https://github.com/apple/swift-metrics); actual functionalities are provided by backend implementations.

## Getting started

If you have a server-side Swift application and would like to locate other services within the same system for making HTTP requests or RPCs, then ServiceDiscovery is the right library for the job. Below you will find all you need to know to get started.

### Concepts

- **Service Identity**: Each service must have a unique identity. `Service` denotes the identity type used in a backend implementation.
- **Service Instance**: A service may have zero or more instances, each of which has an associated location (typically host-port). `Instance` denotes the service instance type used in a backend implementation.

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

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`):

```swift
serviceDiscovery.lookup(service) { result in
    ...
}
```

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`) **AND** subscribe to future changes:

```swift
let cancellationToken = serviceDiscovery.subscribe(
    to: service,
    onNext: { result in
        // This closure gets invoked once at the beginning and subsequently each time a change occurs
        ...
    },
    onComplete: { reason in
        // This closure gets invoked when the subscription completes
        ...
    }
)

...

// Cancel the `subscribe` request
cancellationToken.cancel()
```

`subscribe` returns a ``CancellationToken`` that you can use to cancel the subscription later on. `onComplete` is a closure that
gets invoked when the subscription ends (e.g., when the service discovery instance shuts down) or gets cancelled through the
``CancellationToken``. ``CompletionReason`` can be used to distinguish what leads to the completion.
                                            
#### Async APIs

Async APIs are available for Swift 5.5 and above.
                                                
To fetch the current list of instances:
                                            
```swift
let instances: [Instance] = try await serviceDiscovery.lookup(service)
```
   
To fetch the current list of instances **AND** subscribe to future changes:
                                                
```swift
for try await instances in serviceDiscovery.subscribe(to: service) {
    // do something with this snapshot of instances
}
```
                                            
Underlying the async `subscribe` API is an `AsyncSequence`. To end the subscription, simply break out of the `for`-loop.

### Combinators

ServiceDiscovery includes combinators for common requirements such as transforming and filtering instances. For example:

```swift
// Only include instances running on port 8080
let serviceDiscovery = InMemoryServiceDiscovery(configuration: configuration)
    .filterInstance { [8080].contains($0.port) }
```

## Implementing a service discovery backend

> Note: Unless you need to implement a custom service discovery backend, everything in this section is likely not relevant, so please feel free to skip.

### Adding the dependency

To add a dependency on the API package, you need to declare it in your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-service-discovery.git", from: "0.1.0"),
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

To become a compatible service discovery backend that all ServiceDiscovery consumers can use, you need to implement a type that conforms to the ``ServiceDiscovery/ServiceDiscovery`` protocol provided by ServiceDiscovery. It includes two methods, ``ServiceDiscovery/lookup(_:deadline:callback:)`` and ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.

#### lookup

```swift
/// Performs a lookup for the given service's instances. The result will be sent to `callback`.
///
/// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
///
/// - Parameters:
///   - service: The service to lookup
///   - deadline: Lookup is considered to have timed out if it does not complete by this time
///   - callback: The closure to receive lookup result
func lookup(_ service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)
```

`lookup` fetches the current list of instances for the given `service` and sends it to `callback`. If the service is unknown (e.g., registration is required but it has not been done for the service), then the result should be a `LookupError.unknownService` failure.

The backend implementation should impose a deadline on when the operation will complete. `deadline` should be respected if given, otherwise one should be computed using `defaultLookupTimeout`.

#### subscribe

```swift
/// Subscribes to receive a service's instances whenever they change.
///
/// The service's current list of instances will be sent to `nextResultHandler` when this method is first called. Subsequently,
/// `nextResultHandler` will only be invoked when the `service`'s instances change.
///
/// ### Threading
///
/// `nextResultHandler` and `completionHandler` may be invoked on arbitrary threads, as determined by implementation.
///
/// - Parameters:
///   - service: The service to subscribe to
///   - nextResultHandler: The closure to receive update result
///   - completionHandler: The closure to invoke when the subscription completes (e.g., when the `ServiceDiscovery` instance exits, etc.),
///                 including cancellation requested through `CancellationToken`.
///
/// -  Returns: A `CancellationToken` instance that can be used to cancel the subscription in the future.
func subscribe(to service: Service, onNext nextResultHandler: @escaping (Result<[Instance], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken
```

`subscribe` "pushes" service instances to the `nextResultHandler`. The backend implementation is expected to call `nextResultHandler`:

- When `subscribe` is first invoked, the caller should receive the current list of instances for the given service. This is essentially the `lookup` result.
- Whenever the given service's list of instances changes. The backend implementation has full control over how and when its service records get updated, but it must notify `nextResultHandler` when the instances list becomes different from the previous result.

A new ``CancellationToken`` must be created for each `subscribe` request. If the cancellation token's `isCancelled` is `true`, the subscription has been cancelled and the backend implementation should cease calling the corresponding `nextResultHandler`.

The backend implementation must also notify via `completionHandler` when the subscription ends for any reason (e.g., the service discovery instance is shutting down or cancellation is requested through ``CancellationToken``), so that the subscriber can submit another `subscribe` request if needed.

## Topics

### Service Discovery API

- ``ServiceDiscovery/lookup(_:deadline:callback:)``
- ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``
- ``ServiceDiscovery/lookup(_:deadline:)``
- ``ServiceDiscovery/subscribe(to:)``

### Combinators
                                            
- ``ServiceDiscovery/mapInstance(_:)``
- ``ServiceDiscovery/mapService(serviceType:_:)``
- ``ServiceDiscovery/filterInstance(_:)``

