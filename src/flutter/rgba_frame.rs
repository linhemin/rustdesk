/// Flutter can retain a pointer to the published frame across an async pixel upload.
/// Only its acknowledgement permits that allocation to move back to the decoder.
#[derive(Default, Clone)]
pub(super) struct RgbaData {
    pub(super) data: Vec<u8>,
    pub(super) valid: bool,
    latest: Vec<u8>,
}

impl RgbaData {
    /// Return true when the caller must schedule a Flutter event.
    pub(super) fn offer(&mut self, frame: &mut Vec<u8>, keep_latest: bool) -> bool {
        if frame.is_empty() {
            return false;
        }
        if self.valid {
            if keep_latest {
                std::mem::swap(&mut self.latest, frame);
            }
            return false;
        }
        std::mem::swap(&mut self.data, frame);
        self.valid = true;
        true
    }

    pub(super) fn release(&mut self) -> bool {
        if !self.valid || self.latest.is_empty() {
            self.valid = false;
            return false;
        }
        std::mem::swap(&mut self.data, &mut self.latest);
        self.latest.clear();
        true
    }

    pub(super) fn cancel(&mut self) {
        self.valid = false;
        self.latest.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flutter_pointer_stays_valid_and_final_frame_survives_a_stall() {
        let mut slot = RgbaData::default();
        assert!(slot.offer(&mut vec![11; 3], true));
        let ptr = slot.data.as_ptr();
        for n in 12..=21 {
            assert!(!slot.offer(&mut vec![n; n as usize], true));
            assert_eq!(slot.data.as_ptr(), ptr);
            assert_eq!(slot.data, vec![11; 3]);
        }
        assert!(slot.release());
        assert_eq!(slot.data, vec![21; 21]);
        assert!(!slot.release());
        assert!(!slot.valid);
        assert!(!slot.release());
    }

    #[test]
    fn abandoned_and_ordinary_frames_do_not_get_resubmitted() {
        let mut slot = RgbaData::default();
        assert!(slot.offer(&mut vec![1], true));
        assert!(!slot.offer(&mut vec![2], true));
        slot.cancel();
        assert!(!slot.release());
        assert!(slot.offer(&mut vec![3], false));
        assert!(!slot.offer(&mut vec![4], false));
        assert!(!slot.release());
        assert!(slot.offer(&mut vec![5], true));
        assert_eq!(slot.data, vec![5]);
    }
}
