#include "pch.h"
#include <msiquery.h>
#include <setupapi.h>
#include <newdev.h>
#include <devguid.h>
#include <string>

#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "newdev.lib")

namespace {
constexpr wchar_t Instance[] = L"ROOT\\MEDIA\\RustDeskPhoneMicrophone";
constexpr wchar_t Hardware[] = L"ROOT\\RustDeskPhoneMicrophone\0";

struct Devices {
    HDEVINFO list = SetupDiCreateDeviceInfoList(&GUID_DEVCLASS_MEDIA, nullptr);
    SP_DEVINFO_DATA device{sizeof(SP_DEVINFO_DATA)};
    ~Devices() {
        if (list != INVALID_HANDLE_VALUE) SetupDiDestroyDeviceInfoList(list);
    }
    bool open() {
        return SetupDiOpenDeviceInfoW(list, Instance, nullptr, 0, &device) != FALSE;
    }
};
}

UINT __stdcall DetectPhoneMicrophone(MSIHANDLE install) {
    Devices devices;
    if (devices.list == INVALID_HANDLE_VALUE) return ERROR_INSTALL_FAILURE;
    if (devices.open()) return MsiSetPropertyW(install, L"RD_MIC_PRESENT", L"1");
    return GetLastError() == ERROR_NO_SUCH_DEVINST ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE;
}

UINT __stdcall InstallPhoneMicrophone(MSIHANDLE install) {
    DWORD size = 0;
    wchar_t empty = 0;
    if (MsiGetPropertyW(install, L"CustomActionData", &empty, &size) != ERROR_MORE_DATA || !size)
        return ERROR_INSTALL_FAILURE;
    std::wstring path(size + 1, L'\0');
    ++size;
    if (MsiGetPropertyW(install, L"CustomActionData", &path[0], &size) != ERROR_SUCCESS)
        return ERROR_INSTALL_FAILURE;

    Devices devices;
    if (devices.list == INVALID_HANDLE_VALUE) return ERROR_INSTALL_FAILURE;
    const bool existing = devices.open();
    if (!existing) {
        if (GetLastError() != ERROR_NO_SUCH_DEVINST ||
            !SetupDiCreateDeviceInfoW(devices.list, Instance, &GUID_DEVCLASS_MEDIA, nullptr,
                nullptr, 0, &devices.device) ||
            !SetupDiSetDeviceRegistryPropertyW(devices.list, &devices.device, SPDRP_HARDWAREID,
                reinterpret_cast<const BYTE*>(Hardware), sizeof(Hardware)) ||
            !SetupDiCallClassInstaller(DIF_REGISTERDEVICE, devices.list, &devices.device))
            return ERROR_INSTALL_FAILURE;
    }
    BOOL reboot = FALSE;
    if (!UpdateDriverForPlugAndPlayDevicesW(nullptr, Hardware, path.c_str(), 0, &reboot)) {
        if (existing && GetLastError() == ERROR_NO_MORE_ITEMS) {
            wchar_t service[64] = {};
            if (SetupDiGetDeviceRegistryPropertyW(devices.list, &devices.device, SPDRP_SERVICE, nullptr,
                    reinterpret_cast<BYTE*>(service), sizeof(service), nullptr) &&
                _wcsicmp(service, L"RustDeskPhoneMicrophone") == 0)
                return ERROR_SUCCESS;
        }
        if (!existing) SetupDiCallClassInstaller(DIF_REMOVE, devices.list, &devices.device);
        return ERROR_INSTALL_FAILURE;
    }
    if (reboot) MsiSetMode(install, MSIRUNMODE_REBOOTATEND, TRUE);
    return ERROR_SUCCESS;
}

UINT __stdcall RemovePhoneMicrophone(MSIHANDLE) {
    Devices devices;
    if (devices.list == INVALID_HANDLE_VALUE) return ERROR_INSTALL_FAILURE;
    if (!devices.open()) return GetLastError() == ERROR_NO_SUCH_DEVINST ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE;
    return SetupDiCallClassInstaller(DIF_REMOVE, devices.list, &devices.device)
        ? ERROR_SUCCESS : ERROR_INSTALL_FAILURE;
}
