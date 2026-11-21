use std::time::Duration;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub(in crate::live_direct) enum Nat {
    Stable,
    Linear,
    Random,
    Unknown,
}

impl Nat {
    pub(in crate::live_direct) fn measured(counts: Option<[u8; 4]>) -> Self {
        let Some([stable, linear, random, _]) = counts else {
            return Self::Unknown;
        };
        if stable > linear && stable > random {
            Self::Stable
        } else if linear > stable && linear > random {
            Self::Linear
        } else if random > stable && random > linear {
            Self::Random
        } else {
            Self::Unknown
        }
    }

    pub(in crate::live_direct) fn decode(value: u8) -> Option<Self> {
        [Self::Stable, Self::Linear, Self::Random, Self::Unknown]
            .get(usize::from(value))
            .copied()
    }
}

#[derive(Clone, Copy, Debug)]
pub(in crate::live_direct) struct Plan {
    pub(in crate::live_direct) nats: [Nat; 2],
    sockets: [u16; 2],
    seconds: [u64; 2],
    spacing_ms: u64,
}

impl Plan {
    pub(in crate::live_direct) fn new(nats: [Nat; 2]) -> Self {
        use Nat::*;
        let (sockets, seconds, spacing_ms) = match nats {
            [Stable, Stable] => ([8, 8], [5, 5], 50),
            [Stable, Linear] => ([50, 30], [5, 5], 50),
            [Linear, Stable] => ([30, 50], [5, 5], 50),
            [Stable, Random] => ([500, 150], [60, 6], 15),
            [Random, Stable] => ([150, 500], [6, 60], 15),
            [Linear, Linear] => ([30, 30], [10, 10], 35),
            [Linear, Random] => ([250, 300], [20, 20], 20),
            [Random, Linear] => ([300, 250], [20, 20], 20),
            [Random, Random] => ([500, 500], [60, 60], 12),
            _ => ([250, 250], [20, 20], 20),
        };
        Self {
            nats,
            sockets,
            seconds,
            spacing_ms,
        }
    }

    pub(in crate::live_direct) fn decode(data: &[u8]) -> Option<(Self, &[u8])> {
        let [left, right, tail @ ..] = data else {
            return None;
        };
        Some((Self::new([Nat::decode(*left)?, Nat::decode(*right)?]), tail))
    }

    pub(in crate::live_direct) fn header(self) -> [u8; 2] {
        self.nats.map(|nat| nat as u8)
    }

    pub(in crate::live_direct) fn capacity(self, controller: bool) -> u16 {
        self.sockets[usize::from(!controller)]
    }

    pub(in crate::live_direct) fn window(self) -> Duration {
        (self.send_window(true) + self.lead_delay(true, 0))
            .max(self.send_window(false) + self.lead_delay(false, 0))
    }

    pub(in crate::live_direct) fn send_window(self, controller: bool) -> Duration {
        Duration::from_secs(self.seconds[usize::from(!controller)])
    }

    pub(in crate::live_direct) fn spacing(self) -> Duration {
        Duration::from_millis(self.spacing_ms)
    }

    pub(in crate::live_direct) fn lead_delay(self, controller: bool, round: usize) -> Duration {
        use Nat::*;
        let local = self.nats[usize::from(!controller)];
        let peer = self.nats[usize::from(controller)];
        match (round, local, peer) {
            (0, Linear | Random, Stable) => Duration::from_secs(2),
            (1, Stable, Linear | Random) => Duration::from_millis(180),
            (0, Random, Linear) => Duration::from_millis(180),
            _ => Duration::ZERO,
        }
    }

    pub(in crate::live_direct) fn target_port(
        self,
        controller: bool,
        observed: u16,
        latest: u16,
        step: u16,
        slot: usize,
        round: usize,
    ) -> u16 {
        if round == 0 || slot % 2 == 0 {
            return observed;
        }
        match self.nats[usize::from(controller)] {
            Nat::Linear if step != 0 => {
                let offset = 1 + (round.saturating_sub(1) * 16 + slot / 2) % 96;
                let prediction = latest.wrapping_add(step.wrapping_mul(offset as u16));
                if prediction < 1024 {
                    observed
                } else {
                    prediction
                }
            }
            Nat::Random => {
                // A permutation bounds repeat probes while sampling beyond the
                // mappings already exposed by the observation service.
                const SPAN: usize = 65536 - 1024;
                (1024 + (usize::from(latest) + (round * 503 + slot / 2) * 713) % SPAN) as u16
            }
            _ => observed,
        }
    }

    // Choose the same pair on both sides. The peer with fewer sockets repeats
    // through its list, and each following pass tries a different peer offset.
    pub(in crate::live_direct) fn pair(
        controller: bool,
        local: usize,
        peer: usize,
        slot: usize,
        round: usize,
    ) -> (usize, usize) {
        if controller {
            (slot % local, (slot + round) % peer)
        } else {
            ((slot + round) % local, slot % peer)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_plan_is_directional_and_bounded() {
        use Nat::*;
        let profile = Plan::new([Stable, Random]);
        assert_eq!(profile.capacity(true), 500);
        assert_eq!(profile.capacity(false), 150);
        assert_eq!(profile.window(), Duration::from_secs(60));
        assert_eq!(profile.send_window(false), Duration::from_secs(6));
        assert_eq!(profile.lead_delay(false, 0), Duration::from_secs(2));
        assert_eq!(
            Plan::decode(&profile.header()).unwrap().0.nats,
            profile.nats
        );
        assert!(Plan::decode(&[4, 0]).is_none());
        assert_eq!(Nat::measured(Some([0, 2, 1, 4])), Linear);
        assert_eq!(Nat::measured(Some([0, 1, 1, 4])), Unknown);
    }
}
