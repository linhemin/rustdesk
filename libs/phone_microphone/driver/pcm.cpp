#include <ntddk.h>
#include <wdmsec.h>

#pragma comment(lib, "wdmsec.lib")

namespace {
constexpr ULONG PacketSize = 960 * 2 * sizeof(INT32);
constexpr ULONG Capacity = PacketSize * 4;
constexpr ULONG WritePcm = CTL_CODE(FILE_DEVICE_SOUND, 0x902, METHOD_BUFFERED, FILE_WRITE_ACCESS);
UCHAR samples[Capacity];
ULONG head, queued;
KSPIN_LOCK lock;
PDEVICE_OBJECT control;
PDRIVER_DISPATCH original[IRP_MJ_MAXIMUM_FUNCTION + 1];
UNICODE_STRING linkName = RTL_CONSTANT_STRING(L"\\DosDevices\\Global\\RustDeskPhoneMicrophone");
const GUID deviceClass = {0xc9c4cf1d,0x81d8,0x4d86,{0xa0,0x16,0xae,0x2e,0x09,0xe0,0x18,0x8a}};

NTSTATUS dispatch(PDEVICE_OBJECT device, PIRP irp) {
    auto stack = IoGetCurrentIrpStackLocation(irp);
    const auto major = stack->MajorFunction;
    if (device != control) return original[major](device, irp);

    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    if (major == IRP_MJ_CREATE || major == IRP_MJ_CLOSE || major == IRP_MJ_CLEANUP) {
        KIRQL level;
        KeAcquireSpinLock(&lock, &level);
        head = queued = 0;
        KeReleaseSpinLock(&lock, level);
        status = STATUS_SUCCESS;
    } else if (major == IRP_MJ_DEVICE_CONTROL &&
        stack->Parameters.DeviceIoControl.IoControlCode == WritePcm &&
        stack->Parameters.DeviceIoControl.InputBufferLength == PacketSize &&
        irp->AssociatedIrp.SystemBuffer) {
        KIRQL level;
        KeAcquireSpinLock(&lock, &level);
        const ULONG tail = (head + queued) % Capacity;
        const ULONG first = min(PacketSize, Capacity - tail);
        auto input = static_cast<const UCHAR*>(irp->AssociatedIrp.SystemBuffer);
        RtlCopyMemory(samples + tail, input, first);
        RtlCopyMemory(samples, input + first, PacketSize - first);
        queued += PacketSize;
        if (queued > Capacity) {
            head = (head + queued - Capacity) % Capacity;
            queued = Capacity;
        }
        KeReleaseSpinLock(&lock, level);
        status = STATUS_SUCCESS;
    }
    irp->IoStatus.Status = status;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}
}

void ReadPhoneMicrophone(UCHAR* output, ULONG size) {
    KIRQL level;
    KeAcquireSpinLock(&lock, &level);
    const ULONG read = min(queued, size);
    const ULONG first = min(read, Capacity - head);
    RtlCopyMemory(output, samples + head, first);
    RtlCopyMemory(output + first, samples, read - first);
    queued -= read;
    head = (head + read) % Capacity;
    KeReleaseSpinLock(&lock, level);
    RtlZeroMemory(output + read, size - read);
}

NTSTATUS CreatePhoneMicrophone(PDRIVER_OBJECT driver) {
    UNICODE_STRING name = RTL_CONSTANT_STRING(L"\\Device\\RustDeskPhoneMicrophone");
    UNICODE_STRING acl = RTL_CONSTANT_STRING(L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GW;;;IU)");
    KeInitializeSpinLock(&lock);
    NTSTATUS status = IoCreateDeviceSecure(driver, 0, &name, FILE_DEVICE_SOUND,
        FILE_DEVICE_SECURE_OPEN, TRUE, &acl, &deviceClass, &control);
    if (!NT_SUCCESS(status)) return status;
    status = IoCreateSymbolicLink(&linkName, &name);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(control);
        control = nullptr;
        return status;
    }
    // PortCls owns the audio FDOs. Only the companion control device accepts PCM.
    for (ULONG i = 0; i <= IRP_MJ_MAXIMUM_FUNCTION; ++i) {
        original[i] = driver->MajorFunction[i];
        driver->MajorFunction[i] = dispatch;
    }
    control->Flags &= ~DO_DEVICE_INITIALIZING;
    return STATUS_SUCCESS;
}

void DeletePhoneMicrophone(PDRIVER_OBJECT driver) {
    if (!control) return;
    IoDeleteSymbolicLink(&linkName);
    for (ULONG i = 0; i <= IRP_MJ_MAXIMUM_FUNCTION; ++i)
        driver->MajorFunction[i] = original[i];
    IoDeleteDevice(control);
    control = nullptr;
}
