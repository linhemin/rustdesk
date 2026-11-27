# RustDesk phone microphone on Windows

The x64 driver registers one capture endpoint named **RustDesk Phone Microphone** on Windows 11 (build 22000 or later). RustDesk writes 48 kHz stereo PCM to its exclusive control device after the desktop user accepts a phone microphone request. An application can select the endpoint using the normal Windows input device picker. It supplies silence when no phone is sending audio.

## Build the driver

Use a Visual Studio 2022 developer PowerShell with the Windows Driver Kit toolset, MSVC x64 Spectre-mitigated libraries, Git and NuGet on PATH. From the RustDesk checkout, run

```powershell
./libs/phone_microphone/driver/build.ps1 -WorkDirectory C:/build/rustdesk-microphone
```

The script builds a pinned Microsoft audio driver sample with the RustDesk capture changes using WDK 10.0.26100.6584. The unsigned INF, SYS and catalog are in `Windows-driver-samples/audio/simpleaudiosample/x64/Release/package` under the work directory. The sample license accompanies the sources.

## Include the device in the MSI

Use the package returned by Microsoft hardware driver signing. With SignTool from the Windows SDK on PATH, pass its containing directory to the project's Windows packaging script

```powershell
.github/scripts/package-p2p-windows.ps1 -PhoneMicrophoneDriverDirectory C:/build/signed-phone-microphone
```

This step uses the desktop release payload already built by the Windows workflow. The MSI preprocessor verifies both the INF and SYS against the signed catalog. Installation registers the root audio device. The rollback action removes a newly registered device after a failed installation. Uninstall removes the device on commit.

For end-to-end verification, choose the endpoint in a Windows recording application, speak into the phone, then lock the phone while recording. Check the recording after stopping the connection. Repeat with remote control active and with file transfer open first.
