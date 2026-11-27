#include "pch.h"
#include <devguid.h>
#include <msiquery.h>
#include <newdev.h>
#include <setupapi.h>
#include <string>

#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "newdev.lib")

namespace {
constexpr wchar_t HardwareIds[] = L"VBAudioVACWDM\0";
constexpr wchar_t ServiceName[] = L"VBAudioVACMME";

struct DeviceList {
    HDEVINFO handle;
    ~DeviceList() {
        if (handle != INVALID_HANDLE_VALUE) SetupDiDestroyDeviceInfoList(handle);
    }
};

void LogResult(MSIHANDLE install, const wchar_t* message, DWORD error = ERROR_SUCCESS) {
    MSIHANDLE record = MsiCreateRecord(2);
    if (!record) return;
    MsiRecordSetStringW(record, 0, L"VB-CABLE: [1] (Win32 [2])");
    MsiRecordSetStringW(record, 1, message);
    MsiRecordSetInteger(record, 2, static_cast<int>(error));
    MsiProcessMessage(install, INSTALLMESSAGE_INFO, record);
    MsiCloseHandle(record);
}

DWORD FindInstalledCable(bool& installed) {
    DeviceList devices{SetupDiGetClassDevsW(&GUID_DEVCLASS_MEDIA, nullptr, nullptr, DIGCF_PRESENT)};
    if (devices.handle == INVALID_HANDLE_VALUE) return GetLastError();
    SP_DEVINFO_DATA device{sizeof(device)};
    for (DWORD index = 0; SetupDiEnumDeviceInfo(devices.handle, index, &device); ++index) {
        wchar_t service[256] = {};
        DWORD type = 0;
        if (SetupDiGetDeviceRegistryPropertyW(devices.handle, &device, SPDRP_SERVICE, &type,
                reinterpret_cast<BYTE*>(service), sizeof(service), nullptr) &&
            type == REG_SZ && _wcsicmp(service, ServiceName) == 0) {
            installed = true;
            return ERROR_SUCCESS;
        }
    }
    const DWORD error = GetLastError();
    return error == ERROR_NO_MORE_ITEMS ? ERROR_SUCCESS : error;
}
}

UINT __stdcall InstallVBCable(MSIHANDLE install) {
    bool installed = false;
    const DWORD detection = FindInstalledCable(installed);
    if (detection != ERROR_SUCCESS) {
        LogResult(install, L"could not check existing audio devices", detection);
        return ERROR_INSTALL_FAILURE;
    }
    if (installed) {
        LogResult(install, L"existing standard device found, installation skipped");
        return ERROR_SUCCESS;
    }

    DWORD length = 0;
    wchar_t empty = 0;
    if (MsiGetPropertyW(install, L"CustomActionData", &empty, &length) != ERROR_MORE_DATA || !length)
        return ERROR_INSTALL_FAILURE;
    std::wstring inf(length + 1, L'\0');
    ++length;
    if (MsiGetPropertyW(install, L"CustomActionData", &inf[0], &length) != ERROR_SUCCESS)
        return ERROR_INSTALL_FAILURE;

    DeviceList devices{SetupDiCreateDeviceInfoList(&GUID_DEVCLASS_MEDIA, nullptr)};
    SP_DEVINFO_DATA device{sizeof(device)};
    if (devices.handle == INVALID_HANDLE_VALUE ||
        !SetupDiCreateDeviceInfoW(devices.handle, L"MEDIA", &GUID_DEVCLASS_MEDIA, nullptr,
            nullptr, DICD_GENERATE_ID, &device) ||
        !SetupDiSetDeviceRegistryPropertyW(devices.handle, &device, SPDRP_HARDWAREID,
            reinterpret_cast<const BYTE*>(HardwareIds), sizeof(HardwareIds)) ||
        !SetupDiCallClassInstaller(DIF_REGISTERDEVICE, devices.handle, &device)) {
        LogResult(install, L"could not register the virtual audio device", GetLastError());
        return ERROR_INSTALL_FAILURE;
    }

    BOOL reboot = FALSE;
    if (!UpdateDriverForPlugAndPlayDevicesW(nullptr, HardwareIds, inf.c_str(),
            INSTALLFLAG_NONINTERACTIVE, &reboot)) {
        const DWORD error = GetLastError();
        if (!SetupDiCallClassInstaller(DIF_REMOVE, devices.handle, &device)) {
            LogResult(install, L"could not remove the newly registered device", GetLastError());
        }
        LogResult(install, L"could not install the signed driver", error);
        return ERROR_INSTALL_FAILURE;
    }
    if (reboot) MsiSetMode(install, MSIRUNMODE_REBOOTATEND, TRUE);
    LogResult(install, L"signed standard device installed");
    return ERROR_SUCCESS;
}
