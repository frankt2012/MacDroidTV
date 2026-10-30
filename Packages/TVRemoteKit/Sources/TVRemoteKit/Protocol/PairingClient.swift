import Foundation
import Security

/// Drives the on-screen-code pairing handshake on port 6467.
public actor PairingClient {
    private let host: String
    private let port: UInt16
    private let identity: StoredIdentity
    private let clientName: String

    private var frame: FrameConnection?
    private var serverCertificate: Data?

    public init(
        host: String,
        port: UInt16 = 6467,
        identity: StoredIdentity,
        clientName: String
    ) {
        self.host = host
        self.port = port
        self.identity = identity
        self.clientName = clientName
    }

    /// Connects, asks to pair, and negotiates a 6-character hexadecimal code.
    /// When this returns, the TV is showing the code.
    public func begin(timeout: TimeInterval = 12) async throws {
        let secIdentity: SecIdentity
        do {
            secIdentity = try identity.makeSecIdentity()
        } catch {
            throw TVConnectionError.tls(error.localizedDescription)
        }

        var capturedCertificate: Data?
        let newFrame = try FrameConnection(
            host: host,
            port: port,
            identity: secIdentity,
            onPeerCertificate: { capturedCertificate = $0 }
        )
        frame = newFrame

        do {
            try await newFrame.connect(timeout: timeout)
            guard let certificate = capturedCertificate else {
                throw TVConnectionError.tls("The TV did not present a certificate.")
            }
            serverCertificate = certificate

            var request = OuterMessage()
            request.pairingRequest = PairingRequest(clientName: clientName)
            try await newFrame.send(request.encoded())

            var response = try await receive()
            guard response.pairingRequestAck != nil else {
                throw TVConnectionError.protocolError("The TV did not acknowledge the pairing request.")
            }

            var options = OuterMessage()
            options.options = PairingOptions(
                inputEncodings: [PairingEncoding()],
                preferredRole: 1 // ROLE_TYPE_INPUT
            )
            try await newFrame.send(options.encoded())

            response = try await receive()
            guard response.options != nil else {
                throw TVConnectionError.protocolError("The TV did not send pairing options.")
            }

            var configuration = OuterMessage()
            configuration.configuration = PairingConfiguration(
                encoding: PairingEncoding(),
                clientRole: 1 // ROLE_TYPE_INPUT
            )
            try await newFrame.send(configuration.encoded())

            response = try await receive()
            guard response.configurationAck else {
                throw TVConnectionError.protocolError("The TV did not accept the pairing configuration.")
            }
        } catch {
            newFrame.close()
            frame = nil
            throw error
        }
    }

    /// Sends the secret derived from the code shown on the TV.
    public func finish(code: String) async throws {
        guard let frame, let serverCertificate else {
            throw TVConnectionError.notPaired
        }

        let secret = try PairingSecret.compute(
            clientCertificateDER: identity.certificateDER,
            serverCertificateDER: serverCertificate,
            code: code
        )

        var message = OuterMessage()
        message.secret = secret
        try await frame.send(message.encoded())

        let response = try await receive()
        guard response.secretAck != nil else {
            throw TVConnectionError.pairingRejected
        }

        frame.close()
        self.frame = nil
    }

    public func cancel() {
        frame?.close()
        frame = nil
    }

    public func serverCertificateDER() -> Data? {
        serverCertificate
    }

    private func receive() async throws -> OuterMessage {
        guard let frame else {
            throw TVConnectionError.notPaired
        }
        let data = try await frame.receive(timeout: 15)
        let message = try OuterMessage.decode(data)
        guard message.status == OuterMessage.statusOK else {
            throw TVConnectionError.pairingRejected
        }
        return message
    }
}
