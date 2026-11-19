$ErrorActionPreference = 'Stop'
$payload = (Resolve-Path 'flutter/build/windows/x64/runner/Release').Path
$stage = New-Item -ItemType Directory -Path (Join-Path $env:RUNNER_TEMP 'p2p-msi')
$stock = Join-Path $stage.FullName 'upstream.msi'
$extracted = Join-Path $stage.FullName 'upstream'
$version = '1.5.3'
$asset = "https://github.com/rustdesk/rustdesk/releases/download/$version/rustdesk-$version-x86_64.msi"
Invoke-WebRequest -Uri $asset -OutFile $stock
if ((Get-FileHash $stock -Algorithm SHA256).Hash -ne '27f6bfb48a93d524860dd7f4a79e349be14b6dc71295746cf132a060ba4869c8') {
    throw 'Unexpected upstream MSI digest'
}

# Only the redistributable components come from the pinned upstream installer.
# An administrative extraction in the runner leaves the build's Rust and Flutter files intact.
$arguments = '/a "{0}" /qn /norestart TARGETDIR="{1}"' -f $stock, $extracted
$unpack = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
if ($unpack.ExitCode -ne 0) { throw "Upstream MSI extraction failed with $($unpack.ExitCode)" }
$injection = @(Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter 'WindowInjection.dll')
if ($injection.Count -ne 1) { throw 'Could not identify the upstream component directory' }
$components = $injection[0].Directory.FullName
foreach ($file in @('WindowInjection.dll', 'printer_driver_adapter.dll', 'drivers/RustDeskPrinterDriver/rustdeskprinterdriver.cat', 'usbmmidd_v2/usbmmidd.cat')) {
    if ((Get-AuthenticodeSignature -LiteralPath (Join-Path $components $file)).Status -ne 'Valid') {
        throw "Invalid upstream component signature on $file"
    }
}
foreach ($name in @('WindowInjection.dll', 'printer_driver_adapter.dll', 'drivers', 'usbmmidd_v2')) {
    Copy-Item -LiteralPath (Join-Path $components $name) -Destination $payload -Recurse -Force
}

$output = New-Item -ItemType Directory -Path 'p2p-package' -Force
Push-Location res/msi
try {
    python preprocess.py --arp --version $version -d $payload
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the MSI project' }
    msbuild msi.sln /restore /p:RestorePackagesConfig=true /p:Configuration=Release /p:Platform=x64 /p:TargetVersion=Windows10 /nologo /v:minimal
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the MSI' }
    Copy-Item -LiteralPath 'Package/bin/x64/Release/en-us/Package.msi' -Destination (Join-Path $output.FullName 'rustdesk-1.5.3-physical-ice-windows-x64.msi')
} finally {
    Pop-Location
}
