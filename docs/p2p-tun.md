# Direct connections with a Windows TUN adapter

This opt-in path applies to Windows desktop control sessions made with a RustDesk ID. In **Settings > Network**, unlock the settings and select an Ethernet or Wi-Fi adapter under **Physical adapter for direct connections**. Configure the existing ID server name and public key in **ID/Relay Server**. The client queries the selected adapter's DNS for the server's real public IPv4 address and ignores Fake-IP responses in `198.18.0.0/15`.

For command-line setup, apply the same adapter selection in an elevated PowerShell window.

```powershell
& "$env:ProgramFiles\RustDesk\RustDesk.exe" --option p2p-interface-ip 192.168.50.10
```

Replace the example IP with that device's interface address. If DHCP changes it, select the new address. A previously set `p2p-server-ip` is used as a fallback when adapter DNS cannot resolve the public address. The configured server name, server public key, relay settings and ID registration still govern the session. Registration and relay keep their existing transport paths. A RustDesk proxy or WebSocket configuration takes precedence over the new interface setting.

After saving, allow at least one registration heartbeat before starting a new session to test LAN discovery.

The LAN probe uses the existing LAN discovery protocol. It requires LAN discovery and direct TCP listening to be permitted on the controlled device, plus the matching client and hbbs builds. The probe uses a short-lived listener and verifies the peer's existing RustDesk identity before connection. The ID server passes the temporary port, while the LAN address is learned locally. The original connection attempt is already running when the LAN probe begins. The existing relay fallback delay gives a viable direct attempt priority.

The selected interface is also used for the existing public TCP NAT check and TCP punches. Public UDP and WebRTC signaling in the OSS server follow existing behavior. Use the original ID to connect and confirm the session reports **encrypted direct**. A successful public IPv4 punch depends on the Internet path and both NAT devices.

An official iPhone or iPad controller can keep using the same server, key, and Windows ID. The Windows host uses the selected interface for the existing public TCP punch and for the LAN candidate returned when the ID server selects the original same-network path. If the ID server sees different public source addresses, the official controller uses the existing public TCP path and relay fallback. The new local discovery step for peers with different public source addresses requires both clients to support it.
