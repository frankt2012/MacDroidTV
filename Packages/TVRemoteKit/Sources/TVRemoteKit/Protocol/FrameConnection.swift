import Foundation
import Network
import Security

public enum TVConnectionError: Error, Equatable, LocalizedError {
    case timeout(String)
    case connectionFailed(String)
    case closed
    case tls(String)
    case protocolError(String)
    case notPaired
    case pairingRejected

    public var errorDescription: String? {
        switch self {
        case .timeout(let message):
            return message
        case .connectionFailed(let message):
            return "Could not reach the TV: \(message)"
        case .closed:
            return "The TV closed the connection."
        case .tls(let message):
            return "Secure connection failed: \(message)"
        case .protocolError(let message):
            return "The TV sent an unexpected response: \(message)"
        case .notPaired:
            return "Pair with a TV first."
        case .pairingRejected:
            return "The TV rejected the pairing code."
        }
    }
}

/// A TLS connection that frames each protobuf message with a varint length,
/// matching the Android TV remote protocol.
final class FrameConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.franktriolo.googletvremote.frames")
    private let peerCertificateHandler: ((Data) -> Void)?

    private var buffer = Data()
    private var pendingFrames: [Data] = []
    private var frameWaiter: CheckedContinuation<Data, Error>?
    private var frameTimeoutWork: DispatchWorkItem?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectTimeoutWork: DispatchWorkItem?
    private var terminalError: Error?
    private var receiving = false
    private var didConnect = false

    init(
        host: String,
        port: UInt16,
        identity: SecIdentity?,
        onPeerCertificate: ((Data) -> Void)? = nil
    ) throws {
        peerCertificateHandler = onPeerCertificate

        let tls = NWProtocolTLS.Options()
        let securityOptions = tls.securityProtocolOptions

        if let identity {
            guard let secIdentity = sec_identity_create(identity) else {
                throw TVConnectionError.tls("Could not prepare the client certificate.")
            }
            sec_protocol_options_set_local_identity(securityOptions, secIdentity)
        }

        let certificateHandler = onPeerCertificate
        sec_protocol_options_set_verify_block(securityOptions, { metadata, _, complete in
            if let certificateHandler {
                sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
                    let secCertificate = sec_certificate_copy_ref(certificate).takeRetainedValue()
                    let der = SecCertificateCopyData(secCertificate) as Data
                    certificateHandler(der)
                }
            }
            // The TV uses a self-signed certificate and the pairing secret is
            // what authenticates it. Post-pairing the channel is encrypted but
            // the server identity is not otherwise validated.
            complete(true)
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        tcp.noDelay = true

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false

        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw TVConnectionError.connectionFailed("Invalid port \(port).")
        }

        connection = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: networkPort),
            using: parameters
        )
    }

    func connect(timeout: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.didConnect {
                    continuation.resume()
                    return
                }
                if let terminalError = self.terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }

                self.connectContinuation = continuation
                self.connection.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state)
                }

                let work = DispatchWorkItem { [weak self] in
                    self?.failConnect(TVConnectionError.timeout("Timed out connecting to the TV."))
                }
                self.connectTimeoutWork = work
                self.queue.asyncAfter(deadline: .now() + timeout, execute: work)
                self.connection.start(queue: self.queue)
            }
        }
    }

    func send(_ payload: Data) async throws {
        var framed = Data(ProtoWriter.varint(UInt64(payload.count)))
        framed.append(payload)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if let terminalError = self.terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }

                self.connection.send(content: framed, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(
                            throwing: TVConnectionError.connectionFailed(error.localizedDescription)
                        )
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    func receive(timeout: TimeInterval = 10) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async {
                if let terminalError = self.terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }
                if !self.pendingFrames.isEmpty {
                    continuation.resume(returning: self.pendingFrames.removeFirst())
                    return
                }
                guard self.frameWaiter == nil else {
                    continuation.resume(
                        throwing: TVConnectionError.protocolError("Two reads were started at once.")
                    )
                    return
                }

                self.frameWaiter = continuation
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let waiter = self.frameWaiter else { return }
                    self.frameWaiter = nil
                    waiter.resume(throwing: TVConnectionError.timeout("The TV stopped responding."))
                }
                self.frameTimeoutWork = work
                self.queue.asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }
    }

    func close() {
        queue.async {
            self.terminalError = TVConnectionError.closed
            self.connection.cancel()
            self.failAll(TVConnectionError.closed)
        }
    }

    // MARK: - Private

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            didConnect = true
            connectTimeoutWork?.cancel()
            connectContinuation?.resume()
            connectContinuation = nil
            startReceiving()

        case .failed(let error):
            failConnect(TVConnectionError.connectionFailed(error.localizedDescription))
            failAll(TVConnectionError.connectionFailed(error.localizedDescription))

        case .cancelled:
            failConnect(TVConnectionError.closed)
            failAll(TVConnectionError.closed)

        case .waiting:
            // Keep waiting: macOS may be showing the local-network permission
            // prompt, and the connection resumes once it is answered.
            break

        default:
            break
        }
    }

    private func startReceiving() {
        guard !receiving else { return }
        receiving = true

        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                self.receiving = false

                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drainFrames()
                }

                if let error {
                    self.failAll(TVConnectionError.connectionFailed(error.localizedDescription))
                    return
                }
                if isComplete {
                    self.failAll(TVConnectionError.closed)
                    return
                }

                self.startReceiving()
            }
        }
    }

    private enum FrameLength {
        case needMore
        case invalid
        case length(bytes: Int, header: Int)
    }

    private static func decodeFrameLength(_ data: Data) -> FrameLength {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = data.startIndex

        while index < data.endIndex {
            let byte = data[index]
            value |= UInt64(byte & 0x7F) << shift

            if byte & 0x80 == 0 {
                guard let length = Int(exactly: value), length >= 0, length <= 16 * 1024 * 1024 else {
                    return .invalid
                }
                let header = data.distance(from: data.startIndex, to: data.index(after: index))
                return .length(bytes: length, header: header)
            }

            shift += 7
            if shift >= 64 {
                return .invalid
            }
            index = data.index(after: index)
        }

        return .needMore
    }

    private func drainFrames() {
        while true {
            switch Self.decodeFrameLength(buffer) {
            case .needMore:
                return

            case .invalid:
                failAll(TVConnectionError.protocolError("Malformed message length."))
                return

            case .length(let length, let header):
                guard buffer.count >= header + length else { return }
                let start = buffer.index(buffer.startIndex, offsetBy: header)
                let end = buffer.index(start, offsetBy: length)
                let frame = Data(buffer[start..<end])
                buffer.removeFirst(header + length)
                deliver(frame)
            }
        }
    }

    private func deliver(_ frame: Data) {
        if let waiter = frameWaiter {
            frameWaiter = nil
            frameTimeoutWork?.cancel()
            waiter.resume(returning: frame)
        } else {
            pendingFrames.append(frame)
        }
    }

    private func failConnect(_ error: Error) {
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        connectTimeoutWork?.cancel()
        continuation.resume(throwing: error)
    }

    private func failAll(_ error: Error) {
        if terminalError == nil {
            terminalError = error
        }
        failConnect(error)

        if let waiter = frameWaiter {
            frameWaiter = nil
            frameTimeoutWork?.cancel()
            waiter.resume(throwing: error)
        }
    }

    deinit {
        connection.cancel()
    }
}
