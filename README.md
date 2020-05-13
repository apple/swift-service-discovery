# SwiftServiceDiscovery

A Service Discovery API for Swift. 

Service discovery is how services locate one another within a distributed system. This API library is designed to establish a standard that can be implemented by various service discovery backends such as DNS-based, key-value store using Zookeeper, etc. In other words, this library defines the API only, similar to [SwiftLog](https://github.com/apple/swift-log) and [SwiftMetrics](https://github.com/apple/swift-metrics); actual functionalities are provided by backend implementations. 

This is the beginning of a community-driven open-source project actively seeking contributions, be it code, documentation, or ideas. Apart from contributing to SwiftServiceDiscovery itself, we need SwiftServiceDiscovery-compatible libraries which manage service registration and location information for querying. What SwiftServiceDiscovery provides today is covered in the [API docs][api-docs], but it will continue to evolve with community input.

## Getting started

If you have a server-side Swift application and would like to locate other services within the same system for making HTTP requests or RPCs, then SwiftServiceDiscovery is the right library for the job. Below you will find all you need to know to get started.

### Adding the dependency

To add a dependency on the API package, you need to declare it in your `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-service-discovery.git", from: "1.0.0"),
```

and to your application/library target, add "ServiceDiscovery" to your dependencies:

```swift
.target(name: "MyApplication", dependencies: ["ServiceDiscovery"]),
```

### Concepts

- **Service Identity**: Each service must have a unique identity. `Service` denotes the identity type used in a backend implementation.  
- **Service Instance**: A service may have zero or more instances, each of which has an associated location (typically host-port). `Instance` denotes the service instance type used in a backend implementation. 

### Obtaining a service's instances

```swift
// 1) Let's import the service discovery API package
import ServiceDiscovery

// 2) We need to create a concrete ServiceDiscovery object
let serviceDiscovery = SelectedServiceDiscoveryImplementation()
```

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`):

```swift
serviceDiscovery.lookup(service: service) { result in
    ...
}
```

To fetch the current list of instances (where `result` is `Result<[Instance], Error>`) AND subscribe to future changes:

```swift
serviceDiscovery.subscribe(service: service) { result in
    // This closure gets invoked once at the beginning and subsequently each time a change occurs
    ...
}
```

### Selecting a service discovery backend implementation (applications only)

> Note: If you are building a library, you don't need to concern yourself with this section. It is the end users of your library (the applications) who will decide which service discovery backend to use. Libraries should never change the service discovery implementation as that is something owned by the application.

SwiftServiceDiscovery only provides the service discovery API. As an application owner, you need to select a service discovery backend (such as the ones mentioned above) to make querying available.

Selecting a backend is done by adding a dependency on the desired backend implementation and instantiating it at the beginning of the program:

```
let serviceDiscovery = SelectedServiceDiscoveryImplementation()
```

As the API has just launched, not many implementations exist yet. If you are interested in implementing one see the "Implementing a service discovery backend" section below explaining how to do so. List of existing SwiftServiceDiscovery API compatible libraries:

- Your library? Get in touch!

## Implementing a service discovery backend

> Note: Unless you need to implement a custom service discovery backend, everything in this section is likely not relevant, so please feel free to skip.

To become a compatible service discovery backend that all SwiftServiceDiscovery consumers can use, you need to implement a type that conforms to the `ServiceDiscovery` protocol provided by SwiftServiceDiscovery. It includes two methods, `lookup` and `subscribe`.

#### `lookup`

```
/// Performs a lookup for the `service`'s instances. The result will be sent to `callback`.
///
/// `defaultLookupTimeout` will be used to compute `deadline` in case one is not specified.
func lookup(service: Service, deadline: DispatchTime?, callback: @escaping (Result<[Instance], Error>) -> Void)
```

`lookup` fetches the current list of instances for the given service and sends it to `callback`. If the service is not registered, then the result should be a `LookupError.unknownService` failure. 

The backend implementation should impose a deadline on when the operation will complete. `deadline` should be respected if given, otherwise one should be computed using `defaultLookupTimeout`. 

#### `subscribe`

```
/// Subscribes to receive `service`'s instances whenever they change.
///
/// `lookup` will be called once and its results sent to `handler` when this method is first invoked. Subsequently, `handler`
/// will only receive updates when the `service`'s instances change.
mutating func subscribe(service: Service, handler: @escaping (Result<[Instance], Error>) -> Void)
```

`subscribe` "pushes" service instances to the `handler`. The backend implementation is expected to call `handler`:

- When `subscribe` is first invoked, the caller should receive the current list of instances for the given service. This is essentially the `lookup`  result.
- Whenever the given service's list of instances changes. The backend implementation has full control over how and when its service records get updated, but it must notify `handler` when the instances list becomes different from the previous result. 

If all that a backend needs to do is perform `lookup` at fixed interval (e.g., run a DNS query), you may consider conforming to the `PollingServiceDiscovery` protocol which provides default implementation for `subscribe`.  

Do not hesitate to get in touch, over on https://forums.swift.org/c/server.

[api-docs]: https://apple.github.io/swift-service-discovery/docs/current/ServiceDiscovery/ServiceDiscovery/index.html
