//
//  NetworkInterfaceLister.swift
//  HiFidelity
//
//  Enumerates active IPv4 addresses on user-relevant interfaces. We use
//  `getifaddrs` (POSIX) instead of `NWPathMonitor` paths because the
//  latter does not expose individual addresses.
//

import Foundation
import Darwin

enum NetworkInterfaceLister {
    /// Return the IPv4 addresses on interfaces a remote client could
    /// reasonably reach us through: ethernet/Wi-Fi (`en*`), VPN tunnels
    /// (`utun*`), bridges (`bridge*`). Loopback and Apple-internal
    /// awdl/llw/ap/gif/stf interfaces are filtered out.
    static func activeIPv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var results: [String] = []
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = node {
            defer { node = cur.pointee.ifa_next }

            let nameC = cur.pointee.ifa_name
            let name = nameC != nil ? String(cString: nameC!) : ""
            guard isAcceptableInterface(name) else { continue }

            // Must have an address and be IPv4.
            guard let saPtr = cur.pointee.ifa_addr else { continue }
            guard saPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            // Must be up and running.
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }
            // Skip loopback even if it slipped through name filter.
            if (flags & IFF_LOOPBACK) != 0 { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(
                saPtr,
                socklen_t(cur.pointee.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if rc == 0 {
                let ip = String(cString: hostname)
                if !ip.isEmpty, !results.contains(ip) {
                    results.append(ip)
                }
            }
        }
        return results
    }

    /// Whitelist of interface name prefixes that map to user-reachable
    /// network paths. Apple-internal helper interfaces are excluded.
    private static func isAcceptableInterface(_ name: String) -> Bool {
        if name.hasPrefix("en") { return true }     // Ethernet + Wi-Fi
        if name.hasPrefix("utun") { return true }   // VPN tunnels (Tailscale, IPsec)
        if name.hasPrefix("bridge") { return true } // Internet sharing bridges
        return false
    }
}
