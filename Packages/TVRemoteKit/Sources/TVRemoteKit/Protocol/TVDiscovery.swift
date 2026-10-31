import Foundation
import Network

/// Finds TVs advertising the Android TV remote service over Bonjour.
public final class TVDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.franktriolo.googletvremote.discovery")
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private var devices: [String: DiscoveredDevice] = [:]

    public var onChange: (([DiscoveredDevice]) -> Void)?

    public init() {}

    public func start() {
        stop()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false

        let browser = NWBrowser(
            for: .bonjour(type: "_androidtvremote2._tcp", domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { state in
            if case .failed = state {
                // Discovery is a convenience; the user can always type an IP.
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.queue.async {
                self?.update(results)
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        queue.async {
            self.endpoints.removeAll()
            self.devices.removeAll()
            self.onChange?([])
        }
    }

    /// Resolves a Bonjour service to an address by briefly opening a TCP
    /// connection to it. Returns nil if the service disappeared.
    public func resolveHost(for serviceName: String, timeout: TimeInterval = 5) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let endpoint = self.endpoints[serviceName] else {
                    continuation.resume(returning: nil)
                    return
                }

                let connection = NWConnection(to: endpoint, using: .tcp)
                var finished = false

                func finish(_ host: String?) {
                    guard !finished else { return }
                    finished = true
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    continuation.resume(returning: host)
                }

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint {
                            finish(Self.string(for: host))
                        } else {
                            finish(nil)
                        }
                    case .failed, .cancelled:
                        finish(nil)
                    default:
                        break
                    }
                }

                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    finish(nil)
                }
            }
        }
    }

    // MARK: - Private

    private func update(_ results: Set<NWBrowser.Result>) {
        var newEndpoints: [String: NWEndpoint] = [:]
        var newDevices: [String: DiscoveredDevice] = [:]

        for result in results {
            guard case let .service(serviceName, _, _, _) = result.endpoint else {
                continue
            }

            newEndpoints[serviceName] = result.endpoint

            var displayName = serviceName
            var txt: [String: String] = [:]
            if case let .bonjour(metadata) = result.metadata {
                for (key, value) in metadata.dictionary {
                    txt[key] = value
                }
                if let advertisedName = metadata["name"], !advertisedName.isEmpty {
                    displayName = advertisedName
                }
            }

            newDevices[serviceName] = DiscoveredDevice(
                serviceName: serviceName,
                name: displayName,
                host: devices[serviceName]?.host,
                txt: txt
            )
        }

        endpoints = newEndpoints
        devices = newDevices

        let sorted = newDevices.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        onChange?(sorted)
    }

    private static func string(for host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _):
            return name
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        @unknown default:
            return host.debugDescription
        }
    }
}
