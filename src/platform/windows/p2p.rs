use std::net::Ipv4Addr;

pub(super) fn set_unicast_interface(
    socket: &impl std::os::windows::io::AsRawSocket,
    index: u32,
) -> std::io::Result<()> {
    use winapi::um::winsock2::{setsockopt, WSAGetLastError, SOCKET_ERROR};
    const IP_UNICAST_IF: i32 = 31;
    // Winsock takes the IPv4 unicast interface index in network byte order.
    let bytes = index.to_be_bytes();
    let result = unsafe {
        setsockopt(
            socket.as_raw_socket() as usize,
            0,
            IP_UNICAST_IF,
            bytes.as_ptr().cast(),
            4,
        )
    };
    if result == SOCKET_ERROR {
        return Err(std::io::Error::from_raw_os_error(unsafe {
            WSAGetLastError()
        }));
    }
    Ok(())
}

pub(crate) fn bind_p2p_stun_udp(
    source: Ipv4Addr,
    index: u32,
    min: u16,
    max: u16,
) -> Option<hbb_common::tokio::net::UdpSocket> {
    use std::net::UdpSocket;
    let socket = if (min, max) == (0, 0) {
        UdpSocket::bind((source, 0)).ok()?
    } else {
        let first = u32::from(min.max(1));
        let last = u32::from(if max == 0 { u16::MAX } else { max });
        let count = last.checked_sub(first)? + 1;
        let start = hbb_common::rand::random::<u32>() % count;
        // The supplemental path may yield to ordinary gathering if a range is busy.
        (0..count.min(16))
            .find_map(|i| UdpSocket::bind((source, (first + (start + i) % count) as u16)).ok())?
    };
    set_unicast_interface(&socket, index).ok()?;
    socket.set_nonblocking(true).ok()?;
    hbb_common::tokio::net::UdpSocket::from_std(socket).ok()
}

pub(crate) fn is_physical_p2p_interface(index: u32) -> bool {
    use windows::Win32::NetworkManagement::{
        IpHelper::{GetIfEntry2, MIB_IF_ROW2},
        Ndis::IfOperStatusUp,
    };

    let mut row = MIB_IF_ROW2 {
        InterfaceIndex: index,
        ..Default::default()
    };
    let status = unsafe { GetIfEntry2(&mut row) };
    // HardwareInterface is the low bit of InterfaceAndOperStatusFlags.
    status.0 == 0
        && row.OperStatus == IfOperStatusUp
        && row.InterfaceAndOperStatusFlags._bitfield & 1 != 0
}

pub(crate) fn resolve_p2p_ipv4(host: &str, index: u32) -> Vec<(Ipv4Addr, u32)> {
    use windows::{
        core::PCWSTR,
        Win32::NetworkManagement::Dns::{
            DnsFree, DnsFreeRecordList, DnsQueryEx, DNS_QUERY_BYPASS_CACHE,
            DNS_QUERY_NO_HOSTS_FILE, DNS_QUERY_REQUEST, DNS_QUERY_REQUEST_VERSION1,
            DNS_QUERY_RESULT, DNS_QUERY_RESULTS_VERSION1, DNS_QUERY_TREAT_AS_FQDN,
            DNS_QUERY_USE_TCP_ONLY, DNS_QUERY_WIRE_ONLY, DNS_RECORDA, DNS_TYPE_A,
        },
    };

    if index == 0 || host.is_empty() || host.contains('\0') {
        return Vec::new();
    }

    struct Records(*mut DNS_RECORDA);
    impl Drop for Records {
        fn drop(&mut self) {
            if !self.0.is_null() {
                // DnsQueryEx owns this allocation until DnsFree releases the record list.
                unsafe { DnsFree(Some(self.0.cast()), DnsFreeRecordList) };
            }
        }
    }

    let name: Vec<u16> = host.encode_utf16().chain([0]).collect();
    let flags = DNS_QUERY_BYPASS_CACHE.0
        | DNS_QUERY_NO_HOSTS_FILE.0
        | DNS_QUERY_TREAT_AS_FQDN.0
        | DNS_QUERY_USE_TCP_ONLY.0
        | DNS_QUERY_WIRE_ONLY.0;
    let query = DNS_QUERY_REQUEST {
        Version: DNS_QUERY_REQUEST_VERSION1.0,
        QueryName: PCWSTR(name.as_ptr()),
        QueryType: DNS_TYPE_A.0,
        QueryOptions: flags.into(),
        InterfaceIndex: index,
        // With no completion callback, the API consumes the request synchronously.
        ..Default::default()
    };
    let mut result = DNS_QUERY_RESULT {
        Version: DNS_QUERY_RESULTS_VERSION1.0,
        ..Default::default()
    };
    let status = unsafe { DnsQueryEx(&query, &mut result, None) };
    let records = Records(result.pQueryRecords);
    if status != 0 || result.QueryStatus != 0 {
        return Vec::new();
    }

    let mut addresses = Vec::new();
    let mut record = records.0;
    // The records remain valid until the owning list is freed below.
    while let Some(item) = unsafe { record.as_ref() } {
        if item.wType == DNS_TYPE_A.0 && item.wDataLength == 4 {
            let ip = Ipv4Addr::from(unsafe { item.Data.A.IpAddress }.to_ne_bytes());
            addresses.push((ip, item.dwTtl));
        }
        record = item.pNext;
    }
    addresses
}
