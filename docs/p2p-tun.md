# Direct connections with a Windows TUN adapter

This opt-in path applies to Windows desktop control sessions made with a RustDesk ID. In an elevated PowerShell window, configure the selected Ethernet or Wi-Fi IPv4 address and the current real IPv4 address of the configured public ID server.

```powershell
& "$env:ProgramFiles\RustDesk\RustDesk.exe" --option p2p-interface-ip 192.168.50.10
& "$env:ProgramFiles\RustDesk\RustDesk.exe" --option p2p-server-ip 203.0.113.10
Restart-Service RustDesk
```

Replace the example IPs with the actual addresses. Each device uses its own interface IP. Update the server address when its public IPv4 changes. The configured server name, server public key, relay settings and ID registration still govern the session. Registration and relay keep their existing transport paths. A RustDesk proxy or WebSocket configuration takes precedence over the new interface setting.

Close and reopen both desktop clients after updating the options, then allow at least one registration heartbeat before testing LAN discovery.

The LAN probe uses the existing LAN discovery protocol. It requires LAN discovery and direct TCP listening to be permitted on the controlled device, plus the matching client and hbbs builds. The probe uses a short-lived listener and verifies the peer's existing RustDesk identity before connection. The ID server passes the temporary port, while the LAN address is learned locally. The original connection attempt is already running when the LAN probe begins. The existing relay fallback delay gives a viable direct attempt priority.

The selected interface is also used for the existing public TCP NAT check and TCP punches. Public UDP and WebRTC signaling in the OSS server follow existing behavior. Use the original ID to connect and confirm the session reports **encrypted direct**. A successful public IPv4 punch depends on the Internet path and both NAT devices.
