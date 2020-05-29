# SwiftServiceDiscovery

A Service Discovery API for Swift. 

Service discovery is how services locate one another within a distributed system. This API library is designed to establish a standard that can be implemented by various service discovery backends such as DNS-based, key-value store using Zookeeper, etc. In other words, this library defines the API only, similar to [SwiftLog](https://github.com/apple/swift-log) and [SwiftMetrics](https://github.com/apple/swift-metrics); actual functionalities are provided by backend implementations. 

This is the beginning of a community-driven open-source project actively seeking contributions, be it code, documentation, or ideas. Apart from contributing to SwiftServiceDiscovery itself, we need SwiftServiceDiscovery-compatible libraries which manage service registration and location information for querying. What SwiftServiceDiscovery provides today is covered in the [API docs][api-docs], but it will continue to evolve with community input.

## Getting started

If you have a server-side Swift application and would like to locate other services within the same system for making HTTP requests or RPCs, then SwiftServiceDiscovery is the right library for the job. Below you will find all you need to know to get started.

### Concepts

- **Service Identity**: Each service must have a unique identity. `Service` denotes the identity type used in a backend implementation.
- **Service Instance**: A service may have zero or more instances, each of which has an associated location (typically host-port). `Instance` denotes the service instance type used in a backend implementation. 

### Selecting a service discovery backend implementation (applications only)

> Note: If you are building a library, you don't need to concern yourself with this section. It is the end users of your library (the applications) who will decide which service discovery backend to use. Libraries should never change the service discovery implementation as that is something owned by the application.

SwiftServiceDiscovery only provides the service discovery API. As an application owner, you need to select a service discovery backend to make querying available.

Selecting a backend is done by adding a dependency on the desired backend implementation and instantiating it at the beginning of the program. 

For example, suppose you have chosen the hypothetical `DNSBasedServiceDiscovery` as the backend: 

```swift
// 1) Import the service discovery backend package
import DNSBasedServiceDiscovery

// 2) Create a concrete ServiceDiscovery object
let serviceDiscovery = DNSBasedServiceDiscovery()
```

As the API has just launched, not many implementations exist yet. If you are interested in implementing one see the "Implementing a service discovery backend" section below explaining how to do so. List of existing SwiftServiceDiscovery API compatible libraries:

- Your library? Get in touch!

### Obtaining a service's instances

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`):

```swift
serviceDiscovery.lookup(service) { result in
    ...
}
```

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`) AND subscribe to future changes:

```swift
let token = serviceDiscovery.subscribe(
    to: service, 
    onNext: { result in
        // This closure gets invoked once at the beginning and subsequently each time a change occurs
        ...
    },
    onComplete: {
        // This closure gets invoked when the subscription completes
        ...
    }
}
```

`subscribe` returns a `CancellationToken` that you can use to cancel thesubscription later on. `onComplete` is a closure that
gets invoked when the subscription ends (e.g., when the service discovery instance shuts down).

## Implementing a service discovery backend

> Note: Unless you need to implement a custom service discovery backend, everything in this section is likely not relevant, so please feel free to skip.

### Adding the dependency

To add a dependency on the API package, you need to declare it in your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-service-discovery.git", from: "1.0.0"),
```

and to your library target, add "ServiceDiscovery" to your dependencies:

```swift
.target(name: "MyServiceDiscovery", dependencies: ["ServiceDiscovery"]),
```

To become a compatible service discovery backend that all SwiftServiceDiscovery consumers can use, you need to implement a type that conforms to the `ServiceDiscovery` protocol provided by SwiftServiceDiscovery. It includes two methods, `lookup` and `subscribe`.

#### `lookup`

```
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

`lookup` fetches the current list of instances for the given service and sends it to `callback`. If the service is not registered, then the result should be a `LookupError.unknownService` failure. 

The backend implementation should impose a deadline on when the operation will complete. `deadline` should be respected if given, otherwise one should be computed using `defaultLookupTimeout`. 

#### `subscribe`

```
/// Subscribes to receive a service's instances whenever they change.
///
/// The service's current list of instances will be sent to `onNext` when this method is first called. Subsequently,
/// `onNext` will only be invoked when the `service`'s instances change.
///
/// - Parameters:
///   - service: The service to subscribe to
///   - onNext: The closure to receive update result
///   - onComplete: The closure to invoke when the subscription completes (e.g., when the `ServiceDiscovery` instance exits, etc.)
///
/// -  Returns: A `CancellationToken` instance that can be used to cancel the subscription in the future.
func subscribe(to service: Service, onNext: @escaping (Result<[Instance], Error>) -> Void, onComplete: @escaping () -> Void) -> CancellationToken
```

`subscribe` "pushes" service instances to the `handler`. The backend implementation is expected to call `handler`:

- When `subscribe` is first invoked, the caller should receive the current list of instances for the given service. This is essentially the `lookup` result.
- Whenever the given service's list of instances changes. The backend implementation has full control over how and when its service records get updated, but it must notify `handler` when the instances list becomes different from the previous result.

A new `CancellationToken` must be created for each `subscribe` request, and when the token's `isCanceled` is `true`, the subscription has been canceled and the backend implementation should cease calling the corresponding `handler`.

The backend implementation must also notify via `onComplete` when it has to end subscription for any reason (e.g., the service discovery instance is shutting down), so that the subscriber can submit another `subscribe` request if needed.

---

Do not hesitate to get in touch, over on https://forums.swift.org/c/server.

[api-docs]: https://apple.github.io/swift-service-discovery/docs/current/ServiceDiscovery/ServiceDiscovery/index.html
