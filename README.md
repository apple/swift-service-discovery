# SwiftServiceDiscovery

A Service Discovery API for Swift. 

Service discovery is how services locate one another within a distributed system. This API library is designed to establish a standard that can be implemented by various service discovery backends such as DNS-based, key-value store using Zookeeper, etc. In other words, this library defines the API only, similar to [SwiftLog](https://github.com/apple/swift-log) and [SwiftMetrics](https://github.com/apple/swift-metrics); actual functionalities are provided by backend implementations. 

This is the beginning of a community-driven open-source project actively seeking contributions, be it code, documentation, or ideas. Apart from contributing to SwiftServiceDiscovery itself, we need SwiftServiceDiscovery-compatible libraries which manage service registration and location information for querying. What SwiftServiceDiscovery provides today is covered in the [API docs][api-docs], but it will continue to evolve with community input.

## Getting started

If you have a server-side Swift application and would like to locate other services within the same system for making HTTP requests or RPCs, then SwiftServiceDiscovery is  the right library for the job. Below you will find all you need to know to get started.

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

To fetch the current snapshot:

```swift
serviceDiscovery.lookup(service: service) { instances in
    ...
}
```

To fetch the current snapshot AND subscribe to future changes:

```swift
serviceDiscovery.subscribe(service: service, refreshInterval: .seconds(10)) { instances in
    // This get invoked once at the beginning and subsequently each time a change occurs
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

Note: Unless you need to implement a custom service discovery backend, everything in this section is likely not relevant, so please feel free to skip.

To become a compatible service discovery backend that all SwiftServiceDiscovery consumers can use, you need to do implement a type (must be a class) that conforms to `DynamicServiceDiscovery`, a protocol provided by SwiftServiceDiscovery. `DynamicServiceDiscovery` adds the `subscribe` method on top of `ServiceDiscovery` protocol, which provides the fundamental `lookup` method. `subscribe` is already implemented via extension, so the only task you have is implement `lookup`. 

Do not hesitate to get in touch as well, over on https://forums.swift.org/c/server.

[api-docs]: https://apple.github.io/swift-service-discovery/docs/current/ServiceDiscovery/ServiceDiscovery/index.html
