use hbb_common::{libc, log};
use std::{ffi::CStr, net::Ipv4Addr, ptr};

pub(crate) fn lan_ipv4_for_tunnel(source: Ipv4Addr) -> Option<Ipv4Addr> {
    let mut interfaces = ptr::null_mut();
    // Use getifaddrs directly because the SystemConfiguration interface lookup is unavailable on
    // some iOS targets. The list and the addresses in it are valid until freeifaddrs.
    if unsafe { libc::getifaddrs(&mut interfaces) } != 0 {
        log::trace!(
            "getifaddrs for UDP LAN candidate: {}",
            std::io::Error::last_os_error()
        );
        return None;
    }

    let mut tunnel_source = false;
    let mut preferred = None;
    let mut current = interfaces;
    while let Some(interface) = unsafe { current.as_ref() } {
        current = interface.ifa_next;
        let Some(addr) = (unsafe { interface.ifa_addr.as_ref() }) else {
            continue;
        };
        if addr.sa_family as libc::c_int != libc::AF_INET
            || (addr.sa_len as usize) < std::mem::size_of::<libc::sockaddr_in>()
            || interface.ifa_flags & libc::IFF_UP as libc::c_uint == 0
        {
            continue;
        }
        let addr = unsafe { &*interface.ifa_addr.cast::<libc::sockaddr_in>() };
        let ip = Ipv4Addr::from(addr.sin_addr.s_addr.to_ne_bytes());
        if interface.ifa_flags & libc::IFF_POINTOPOINT as libc::c_uint != 0 {
            tunnel_source |= ip == source;
            continue;
        }
        if !ip.is_private()
            || matches!(ip.octets()[3], 0 | 255)
            || interface.ifa_flags & libc::IFF_RUNNING as libc::c_uint == 0
            || interface.ifa_name.is_null()
        {
            continue;
        }
        let name = unsafe { CStr::from_ptr(interface.ifa_name) };
        // Apple uses enN for Ethernet and Wi-Fi. Exclude bridges and other virtual links.
        if let Some(index) = name
            .to_str()
            .ok()
            .and_then(|name| name.strip_prefix("en"))
            .and_then(|index| index.parse::<u32>().ok())
        {
            let candidate = (index, ip);
            preferred = Some(
                preferred.map_or(candidate, |current: (u32, Ipv4Addr)| current.min(candidate)),
            );
        }
    }
    if !interfaces.is_null() {
        unsafe { libc::freeifaddrs(interfaces) };
    }
    preferred.filter(|_| tunnel_source).map(|(_, ip)| ip)
}
