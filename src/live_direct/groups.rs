use super::*;

/// Each bit refers to the same slot on both peers. Ingress counts only valid ICE
/// requests or matched replies on the advertised pair, before peer-reflexive remapping.
#[derive(Clone, Copy, Default, Debug, PartialEq, Eq)]
pub(crate) struct GroupSample {
    count: u8,
    stable: u8,
    changed: u8,
    written: u8,
    delayed: u8,
    pub(super) ingress: Option<u8>,
}

impl GroupSample {
    pub(super) fn bytes(self) -> [u8; 6] {
        [
            self.count,
            self.stable,
            self.changed,
            self.written,
            self.delayed,
            self.ingress.unwrap_or(255),
        ]
    }

    pub(crate) fn decode(data: &[u8]) -> Option<Self> {
        let &[count, stable, changed, written, delayed, received] =
            <&[u8; 6]>::try_from(data).ok()?;
        if count > 3 {
            return None;
        }
        let valid = (1u8 << count) - 1;
        if (stable | changed | written | delayed) & !valid != 0
            || stable & changed != 0
            || (received != 255 && received & !valid != 0)
        {
            return None;
        }
        Some(Self {
            count,
            stable,
            changed,
            written,
            delayed,
            ingress: (received != 255).then_some(received),
        })
    }
}

impl fmt::Display for GroupSample {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "count={} stableMask={} changedMask={} writtenMask={} delayedMask={} exactIngressMask=",
            self.count, self.stable, self.changed, self.written, self.delayed
        )?;
        match self.ingress {
            Some(mask) => write!(f, "{mask}"),
            None => f.write_str("pending"),
        }
    }
}

fn decode_endpoints(data: &[u8]) -> ResultType<Vec<(SocketAddrV4, u8)>> {
    ensure!(
        !data.is_empty() && data.len() <= 21 && data.len() % 7 == 0,
        "invalid group size"
    );
    let mut endpoints = Vec::new();
    for e in data.chunks_exact(7) {
        let address = SocketAddrV4::new(
            Ipv4Addr::new(e[0], e[1], e[2], e[3]),
            u16::from_be_bytes([e[4], e[5]]),
        );
        ensure!(
            address.port() != 0 && e[6] <= 2 && !endpoints.iter().any(|(addr, _)| addr == &address),
            "invalid group member"
        );
        endpoints.push((address, e[6]));
    }
    Ok(endpoints)
}

// Prefer to open a changing mapping before a more stable peer sends into it.
// With several pairs, reserve a simultaneous slot and try the reverse order as well.
fn offset_ms(slot: usize, count: usize, controller: bool, local: u8, remote: u8) -> u64 {
    let leads = if local == remote {
        controller
    } else {
        local > remote
    };
    let delayed = match (count, slot) {
        (1, 0) => local != remote && !leads,
        (_, 1) => !leads,
        (_, 2) => leads,
        _ => false,
    };
    if delayed {
        100
    } else {
        0
    }
}

impl Exchange<'_> {
    pub(super) async fn group_checks(
        &mut self,
        pc: &WebRTCStream,
        controller: bool,
        remote: &mut mpsc::Receiver<String>,
        held: &mut Vec<String>,
        exact: &mut Vec<(String, SocketAddrV4)>,
        report: &mut GroupSample,
    ) -> ResultType<Sample> {
        let local = loop {
            let local = pc.grouped_public_candidates().await;
            if !local.is_empty() {
                break local;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        };
        if let Some(counts) = pc.ordered_mapping_profiles().await {
            self.send(PROFILE, &counts).await?;
        }
        let mut wire = Vec::new();
        for (_, addr, rank) in &local {
            wire.extend_from_slice(&addr.ip().octets());
            wire.extend_from_slice(&addr.port().to_be_bytes());
            wire.push(*rank);
        }
        self.send(GROUP_SELECT, &wire).await?;
        let (kind, data) = self
            .incoming
            .recv()
            .await
            .context("missing group selection")?;
        ensure!(kind == GROUP_SELECT, "unexpected group frame");
        let mut endpoints = decode_endpoints(&data)?;
        endpoints.truncate(local.len());
        let count = endpoints.len();
        report.count = count as u8;
        let mut lines = vec![None; count];
        while lines.iter().any(Option::is_none) {
            let json = remote.recv().await.context("group trickle ended")?;
            if let Some(addr) = WebRTCStream::public_srflx_endpoint(json.as_bytes()) {
                if let Some(i) = endpoints.iter().position(|(ep, _)| *ep == addr) {
                    lines[i] = Some(held.len());
                }
            }
            held.push(json);
        }
        let (deadline, rtt_ms) = self.deadline(controller).await?;
        let mut order: Vec<usize> = (0..count).collect();
        let offset = |i| offset_ms(i, count, controller, local[0].2, endpoints[0].1);
        order.sort_by_key(|&i| offset(i));
        let mut late_ms = 0;
        for i in order {
            let at = deadline + Duration::from_millis(offset(i));
            if offset(i) != 0 {
                report.delayed |= 1 << i;
            }
            tokio::time::sleep_until(at).await;
            let late = Instant::now()
                .saturating_duration_since(at)
                .as_millis()
                .min(u16::MAX as u128) as u16;
            late_ms = late_ms.max(late);
            let (id, _, rank) = &local[i];
            match rank {
                0 => report.stable |= 1 << i,
                2 => report.changed |= 1 << i,
                _ => (),
            }
            if late <= 60 && pc.timed_first_check(id, &held[lines[i].unwrap()]).await {
                report.written |= 1 << i;
            }
        }
        exact.extend(
            local
                .iter()
                .zip(endpoints)
                .map(|((id, _, _), (ep, _))| (id.clone(), ep)),
        );
        Ok(Sample {
            state: if report.written != 0 {
                1
            } else if late_ms > 60 {
                3
            } else {
                4
            },
            rtt_ms,
            late_ms,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_group_rejects_duplicate_and_invalid_slots() {
        let e = [1, 2, 3, 4, 0, 80, 1];
        assert!(decode_endpoints(&e).is_ok());
        assert!(decode_endpoints(&[e, e].concat()).is_err());
        for bytes in [vec![], vec![0; 7], vec![1; 6], vec![1; 24], vec![255; 7]] {
            assert!(decode_endpoints(&bytes).is_err());
        }
        assert!(GroupSample::decode(&[2, 1, 0, 7, 0, 0]).is_none());
        assert!(GroupSample::decode(&[3, 1, 1, 7, 0, 0]).is_none());
        let good = [3, 1, 4, 7, 4, 2];
        assert_eq!(GroupSample::decode(&good).unwrap().bytes(), good);
    }

    #[test]
    fn group_slots_include_both_first_senders() {
        for n in 1..=3 {
            for a in 0..=2 {
                for b in 0..=2 {
                    for slot in 0..n {
                        let x = offset_ms(slot, n, true, a, b);
                        let y = offset_ms(slot, n, false, b, a);
                        if slot == 0 && (n > 1 || a == b) {
                            assert_eq!((x, y), (0, 0));
                        } else {
                            assert_eq!(x + y, 100);
                        }
                    }
                }
            }
        }
        assert_eq!(offset_ms(0, 1, false, 2, 0), 0);
        assert_eq!(offset_ms(1, 2, false, 2, 0), 0);
        assert_eq!(offset_ms(2, 3, false, 2, 0), 100);
    }
}
