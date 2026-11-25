use super::{wrap_hresult, ComPtr};
use std::{
    ffi::c_void,
    io::{self, ErrorKind},
    mem, ptr,
    sync::{Arc, Condvar, Mutex},
    thread::{self, JoinHandle},
    time::Duration,
};
use winapi::{
    shared::{
        dxgi::{IDXGIResource, IDXGISurface, IID_IDXGISurface, DXGI_MAPPED_RECT, DXGI_MAP_READ},
        dxgi1_2::{IDXGIOutputDuplication, DXGI_OUTDUPL_DESC, DXGI_OUTDUPL_FRAME_INFO},
        dxgiformat::DXGI_FORMAT_B8G8R8A8_UNORM,
        dxgitype::{DXGI_MODE_ROTATION_IDENTITY, DXGI_MODE_ROTATION_UNSPECIFIED, DXGI_SAMPLE_DESC},
        guiddef::GUID,
        minwindef::{BOOL, TRUE},
    },
    um::{
        d3d11::{
            ID3D11Device, ID3D11DeviceContext, ID3D11Texture2D, IID_ID3D11Texture2D,
            D3D11_BIND_RENDER_TARGET, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ,
            D3D11_TEXTURE2D_DESC, D3D11_USAGE_DEFAULT, D3D11_USAGE_STAGING,
        },
        unknwnbase::{IUnknown, IUnknownVtbl},
    },
};

const SLOTS: usize = 3;
const CAPTURE_POLL_INTERVAL: Duration = Duration::from_millis(2);

#[derive(Default)]
struct Mailbox {
    ready: Option<usize>,
    reading: Option<usize>,
    failure: Option<io::Error>,
    stopping: bool,
    desktop_updates: usize,
}

impl Mailbox {
    fn write_slot(&self) -> Option<usize> {
        (0..SLOTS).find(|&slot| self.ready != Some(slot) && self.reading != Some(slot))
    }

    fn read_latest(&mut self) -> Option<usize> {
        self.reading = self.ready.take();
        self.reading
    }
}

type Shared = (Mutex<Mailbox>, Condvar);
type Textures = [ComPtr<ID3D11Texture2D>; SLOTS];

struct CaptureResources {
    duplication: ComPtr<IDXGIOutputDuplication>,
    context: ComPtr<ID3D11DeviceContext>,
    textures: Textures,
    width: u32,
    height: u32,
}

// Only the worker calls AcquireNextFrame or ReleaseFrame. The encoder and worker
// share the D3D11 immediate context with multithread protection enabled, and their
// texture accesses are ordered by the mailbox. Each COM reference is owned.
unsafe impl Send for CaptureResources {}

pub(super) struct LatestFrameCapture {
    textures: Textures,
    shared: Arc<Shared>,
    worker: Option<JoinHandle<()>>,
    device: ComPtr<ID3D11Device>,
    context: ComPtr<ID3D11DeviceContext>,
    readback: Option<PixelReadback>,
}

impl LatestFrameCapture {
    pub(super) unsafe fn start(
        duplication: &ComPtr<IDXGIOutputDuplication>,
        device: &ComPtr<ID3D11Device>,
        context: &ComPtr<ID3D11DeviceContext>,
    ) -> io::Result<Self> {
        if duplication.is_null() {
            return Err(ErrorKind::Unsupported.into());
        }
        let mut mode: DXGI_OUTDUPL_DESC = mem::zeroed();
        (*duplication.0).GetDesc(&mut mode);
        if mode.ModeDesc.Format != DXGI_FORMAT_B8G8R8A8_UNORM
            || !matches!(
                mode.Rotation,
                DXGI_MODE_ROTATION_IDENTITY | DXGI_MODE_ROTATION_UNSPECIFIED
            )
        {
            return Err(ErrorKind::Unsupported.into());
        }
        let desc = D3D11_TEXTURE2D_DESC {
            Width: mode.ModeDesc.Width,
            Height: mode.ModeDesc.Height,
            MipLevels: 1,
            ArraySize: 1,
            Format: DXGI_FORMAT_B8G8R8A8_UNORM,
            SampleDesc: DXGI_SAMPLE_DESC {
                Count: 1,
                Quality: 0,
            },
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET,
            CPUAccessFlags: 0,
            MiscFlags: 0,
        };
        enable_context_sharing(context.0)?;
        let textures = [
            create_texture(device.0, &desc)?,
            create_texture(device.0, &desc)?,
            create_texture(device.0, &desc)?,
        ];
        let resources = CaptureResources {
            duplication: add_ref(duplication),
            context: add_ref(context),
            textures: textures.each_ref().map(|texture| add_ref(texture)),
            width: desc.Width,
            height: desc.Height,
        };
        let shared = Arc::new((Mutex::new(Mailbox::default()), Condvar::new()));
        let worker_shared = Arc::clone(&shared);
        let worker = thread::Builder::new()
            .name("dxgi-capture".to_owned())
            .spawn(move || resources.run(&worker_shared))?;
        Ok(Self {
            textures,
            shared,
            worker: Some(worker),
            device: add_ref(device),
            context: add_ref(context),
            readback: None,
        })
    }

    pub(super) fn frame(&mut self, timeout_ms: u32) -> io::Result<(*mut c_void, usize)> {
        if let Some(readback) = &mut self.readback {
            readback.unmap()?;
        }
        let (mailbox, ready) = &*self.shared;
        let mut state = mailbox.lock().unwrap();
        // The caller finished submitting the previous texture before requesting another one.
        state.reading = None;
        let (mut state, _) = ready
            .wait_timeout_while(state, Duration::from_millis(timeout_ms as u64), |state| {
                state.ready.is_none() && state.failure.is_none()
            })
            .unwrap();

        super::record_desktop_updates(mem::take(&mut state.desktop_updates));
        if let Some(error) = state.failure.take() {
            return Err(error);
        }
        let slot = state.read_latest().ok_or(ErrorKind::WouldBlock)?;
        #[cfg(feature = "dxgi-diagnostics")]
        super::PREFETCHED_FRAMES.with(|frames| frames.set(frames.get() + 1));
        Ok((self.textures[slot].0 as *mut c_void, 0))
    }

    pub(super) fn pixel_frame(
        &mut self,
        timeout_ms: u32,
        (width, height): (usize, usize),
    ) -> io::Result<(*const u8, i32)> {
        let (source, _) = self.frame(timeout_ms)?;
        let source = source.cast::<ID3D11Texture2D>();
        unsafe {
            if self.readback.is_none() {
                self.readback = Some(PixelReadback::new(self.device.0, source, width, height)?);
            }
            let readback = self.readback.as_mut().ok_or(ErrorKind::InvalidData)?;
            // The mapped staging surface stays separate from the worker's desktop textures.
            (*self.context.0).CopyResource(readback.texture.0.cast(), source.cast());
            let mut rect: DXGI_MAPPED_RECT = mem::zeroed();
            wrap_hresult((*readback.surface.0).Map(&mut rect, DXGI_MAP_READ))?;
            readback.mapped = true;
            if rect.pBits.is_null() || rect.Pitch < (width * 4) as i32 {
                return Err(ErrorKind::Unsupported.into());
            }
            Ok((rect.pBits, rect.Pitch))
        }
    }
}

struct PixelReadback {
    texture: ComPtr<ID3D11Texture2D>,
    surface: ComPtr<IDXGISurface>,
    mapped: bool,
}

impl PixelReadback {
    unsafe fn new(
        device: *mut ID3D11Device,
        source: *mut ID3D11Texture2D,
        width: usize,
        height: usize,
    ) -> io::Result<Self> {
        let mut desc = mem::zeroed::<D3D11_TEXTURE2D_DESC>();
        (*source).GetDesc(&mut desc);
        if desc.Width as usize != width || desc.Height as usize != height {
            return Err(ErrorKind::Unsupported.into());
        }
        desc.Usage = D3D11_USAGE_STAGING;
        desc.BindFlags = 0;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        desc.MiscFlags = 0;
        let texture = create_texture(device, &desc)?;
        let mut surface = ptr::null_mut();
        wrap_hresult((*texture.0).QueryInterface(&IID_IDXGISurface, &mut surface))?;
        Ok(Self {
            texture,
            surface: ComPtr(surface.cast()),
            mapped: false,
        })
    }

    fn unmap(&mut self) -> io::Result<()> {
        if mem::take(&mut self.mapped) {
            wrap_hresult(unsafe { (*self.surface.0).Unmap() })?;
        }
        Ok(())
    }
}

impl Drop for PixelReadback {
    fn drop(&mut self) {
        if let Err(error) = self.unmap() {
            hbb_common::log::warn!("DXGI pixel readback cleanup failed: {error}");
        }
    }
}

impl Drop for LatestFrameCapture {
    fn drop(&mut self) {
        self.shared.0.lock().unwrap().stopping = true;
        if let Some(worker) = self.worker.take() {
            if worker.join().is_err() {
                hbb_common::log::warn!("DXGI capture thread panicked");
            }
        }
    }
}

impl CaptureResources {
    fn run(self, shared: &Shared) {
        let (mailbox, ready) = shared;
        loop {
            let slot = {
                let state = mailbox.lock().unwrap();
                if state.stopping {
                    return;
                }
                state.write_slot()
            };
            let Some(slot) = slot else {
                self.fail(shared, ErrorKind::InvalidData.into());
                return;
            };
            match unsafe { self.capture_into(slot) } {
                Ok(Some(updates)) => {
                    let mut state = mailbox.lock().unwrap();
                    state.desktop_updates = state.desktop_updates.saturating_add(updates as usize);
                    state.ready = Some(slot);
                    ready.notify_one();
                }
                Ok(None) => thread::sleep(CAPTURE_POLL_INTERVAL),
                Err(error) if error.kind() == ErrorKind::TimedOut => {
                    thread::sleep(CAPTURE_POLL_INTERVAL);
                }
                Err(error) => {
                    self.fail(shared, error);
                    return;
                }
            }
        }
    }

    fn fail(&self, shared: &Shared, error: io::Error) {
        shared.0.lock().unwrap().failure = Some(error);
        shared.1.notify_one();
    }

    unsafe fn capture_into(&self, slot: usize) -> io::Result<Option<u32>> {
        let mut info: DXGI_OUTDUPL_FRAME_INFO = mem::zeroed();
        let mut image: *mut IDXGIResource = ptr::null_mut();
        // A blocking acquire on the shared device can starve the encoder.
        wrap_hresult((*self.duplication.0).AcquireNextFrame(0, &mut info, &mut image))?;
        let image = ComPtr(image);
        let copied = if info.AccumulatedFrames == 0 || *info.LastPresentTime.QuadPart() == 0 {
            Ok(None)
        } else {
            self.copy_desktop(&image, slot)
                .map(|()| Some(info.AccumulatedFrames))
        };
        let released = wrap_hresult((*self.duplication.0).ReleaseFrame());
        released.and(copied)
    }

    unsafe fn copy_desktop(&self, image: &ComPtr<IDXGIResource>, slot: usize) -> io::Result<()> {
        if image.is_null() {
            return Err(ErrorKind::InvalidData.into());
        }
        let mut source = ptr::null_mut();
        wrap_hresult((*image.0).QueryInterface(&IID_ID3D11Texture2D, &mut source))?;
        let source = ComPtr(source as *mut ID3D11Texture2D);
        let mut desc: D3D11_TEXTURE2D_DESC = mem::zeroed();
        (*source.0).GetDesc(&mut desc);
        if desc.Width != self.width
            || desc.Height != self.height
            || desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM
            || desc.MipLevels != 1
            || desc.ArraySize != 1
            || desc.SampleDesc.Count != 1
        {
            return Err(ErrorKind::Unsupported.into());
        }

        (*self.context.0).CopyResource(self.textures[slot].0 as *mut _, source.0 as *mut _);
        Ok(())
    }
}

unsafe fn create_texture(
    device: *mut ID3D11Device,
    desc: &D3D11_TEXTURE2D_DESC,
) -> io::Result<ComPtr<ID3D11Texture2D>> {
    let mut texture = ptr::null_mut();
    wrap_hresult((*device).CreateTexture2D(desc, ptr::null(), &mut texture))?;
    Ok(ComPtr(texture))
}

unsafe fn add_ref<T>(resource: &ComPtr<T>) -> ComPtr<T> {
    (*(resource.0 as *mut IUnknown)).AddRef();
    ComPtr(resource.0)
}

// winapi does not declare ID3D11Multithread. The layout and IID come from d3d11_4.h.
#[repr(C)]
struct Multithread {
    vtable: *const MultithreadVtbl,
}

#[repr(C)]
struct MultithreadVtbl {
    base: IUnknownVtbl,
    enter: unsafe extern "system" fn(*mut Multithread),
    leave: unsafe extern "system" fn(*mut Multithread),
    set_protected: unsafe extern "system" fn(*mut Multithread, BOOL) -> BOOL,
    get_protected: unsafe extern "system" fn(*mut Multithread) -> BOOL,
}

unsafe fn enable_context_sharing(context: *mut ID3D11DeviceContext) -> io::Result<()> {
    const IID: GUID = GUID {
        Data1: 0x9b7e4e00,
        Data2: 0x342c,
        Data3: 0x4106,
        Data4: [0xa1, 0x9f, 0x4f, 0x27, 0x04, 0xf6, 0x89, 0xf0],
    };
    let mut multithread = ptr::null_mut();
    wrap_hresult((*context).QueryInterface(&IID, &mut multithread))?;
    let multithread = ComPtr(multithread as *mut Multithread);
    let vtable = &*(*multithread.0).vtable;
    (vtable.set_protected)(multithread.0, TRUE);
    if (vtable.get_protected)(multithread.0) != TRUE {
        return Err(ErrorKind::Unsupported.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocked_encoder_gets_the_newest_frame_and_keeps_its_input_texture() {
        let mut state = Mailbox::default();
        state.ready = state.write_slot();
        let encoding = state.read_latest();
        state.ready = state.write_slot();
        let superseded = state.ready;
        state.ready = state.write_slot();
        assert_ne!(state.ready, superseded);
        assert_ne!(state.ready, encoding);
        assert_eq!(state.reading, encoding);
        let newest = state.ready;
        assert_eq!(state.read_latest(), newest);
        assert_eq!(state.read_latest(), None);
    }
}
