import Foundation

/// Sends a Wake-on-LAN magic packet to a TV that has left the network while in
/// standby.
///
/// The Android TV remote service normally keeps listening in standby, which is
/// what lets a phone wake the TV. Some sets (several TCL models included) drop
/// off the network entirely instead. If their network chip still honours Wake
/// on LAN, a magic packet is the only way back in.
public enum WakeOnLAN {
    /// Builds the 6-byte preamble followed by the MAC repeated 16 times.
    public static func magicPacket(for mac: String) -> Data? {
        guard let bytes = macBytes(mac), bytes.count == 6 else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }
        return packet
    }

    /// Normalises `aa:bb:cc:dd:ee:ff`, `aa-bb-...` and `aabbccddeeff`.
    public static func macBytes(_ mac: String) -> [UInt8]? {
        let hex = mac.filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// Sends the packet to the usual WoL ports on the limited broadcast address
    /// and on every subnet broadcast address this Mac has. Returns the number
    /// of datagrams sent.
    @discardableResult
    public static func send(
        mac: String,
        broadcastAddresses: [String]? = nil,
        ports: [UInt16] = [9, 7, 6465]
    ) -> Int {
        guard let packet = magicPacket(for: mac) else { return 0 }
        let broadcastAddresses = broadcastAddresses ?? localBroadcastAddresses()

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var sent = 0
        for address in broadcastAddresses {
            for port in ports {
                var target = sockaddr_in()
                target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                target.sin_family = sa_family_t(AF_INET)
                target.sin_port = port.bigEndian
                target.sin_addr.s_addr = inet_addr(address)

                let result = packet.withUnsafeBytes { buffer -> Int in
                    guard let base = buffer.baseAddress else { return -1 }
                    return withUnsafePointer(to: &target) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                            sendto(
                                fd,
                                base,
                                buffer.count,
                                0,
                                sockaddrPointer,
                                socklen_t(MemoryLayout<sockaddr_in>.size)
                            )
                        }
                    }
                }
                if result > 0 { sent += 1 }
            }
        }
        return sent
    }

    /// `255.255.255.255` plus the broadcast address of each IPv4 interface.
    public static func localBroadcastAddresses() -> [String] {
        var addresses = ["255.255.255.255"]
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return addresses }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let sockaddrPointer = current.pointee.ifa_addr,
                  sockaddrPointer.pointee.sa_family == UInt8(AF_INET),
                  current.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  current.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  current.pointee.ifa_flags & UInt32(IFF_BROADCAST) != 0,
                  let broadcastPointer = current.pointee.ifa_dstaddr else { continue }

            let address = broadcastPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            var raw = address
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &raw, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let string = String(cString: buffer)
            if !addresses.contains(string) {
                addresses.append(string)
            }
        }
        return addresses
    }
}
