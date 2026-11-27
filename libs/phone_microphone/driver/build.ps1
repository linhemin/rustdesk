param(
    [ValidateSet('x64', 'ARM64')][string]$Platform = 'x64',
    [Parameter(Mandatory)][string]$WorkDirectory
)
$ErrorActionPreference = 'Stop'
$revision = 'd49bb7d72f3651952b2b6e4ad28d14fe2247eb69'
$source = Join-Path $WorkDirectory 'Windows-driver-samples'
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE)" }
}
if (!(Test-Path -LiteralPath $source)) {
    Invoke-Checked git @('clone', '--no-checkout', '--filter=blob:none',
        'https://github.com/microsoft/Windows-driver-samples.git', $source)
    Invoke-Checked git @('-C', $source, 'sparse-checkout', 'set', 'audio/simpleaudiosample')
    Invoke-Checked git @('-C', $source, 'checkout', '--detach', $revision)
}
if ((git -C $source rev-parse HEAD) -ne $revision) { throw 'Unexpected sample revision' }
$patch = Join-Path $PSScriptRoot 'simple-audio.patch'
git -C $source apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -ne 0) { Invoke-Checked git @('-C', $source, 'apply', $patch) }
$sample = Join-Path $source 'audio/simpleaudiosample'
$main = Join-Path $sample 'Source/Main'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pcm.cpp') -Destination $main
Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'RustDeskPhoneMicrophone.inx') |
    Set-Content -Encoding Unicode -NoNewline -LiteralPath (Join-Path $main 'RustDeskPhoneMicrophone.inx')
# This pinned sample defaults to the VS 2026 WDK. Generate its platform-specific
# package list in the isolated checkout for the VS 2022 kernel toolset.
$kit = '10.0.26100.6584'
$settings = Join-Path $source 'Directory.Build.props'
$props = (Get-Content -Raw -LiteralPath $settings).Replace('10.0.28000.2526', $kit)
Set-Content -LiteralPath $settings -Value $props -Encoding utf8 -NoNewline
$configDir = New-Item -ItemType Directory -Force -Path (Join-Path $WorkDirectory $Platform)
$packageList = Join-Path $configDir.FullName 'packages.config'
[xml]$packages = Get-Content -Raw -LiteralPath (Join-Path $source 'packages.config')
$required = @('Microsoft.Windows.SDK.CPP', "Microsoft.Windows.SDK.CPP.$Platform", "Microsoft.Windows.WDK.$Platform")
foreach ($package in @($packages.packages.package)) {
    if ($required -contains $package.id) { $package.version = $kit }
    else { $null = $packages.packages.RemoveChild($package) }
}
$packages.Save($packageList)
Invoke-Checked nuget @('restore', $packageList,
    '-PackagesDirectory', (Join-Path $source 'packages'), '-NonInteractive')
Invoke-Checked msbuild @((Join-Path $sample 'SimpleAudioSample.sln'),
    '/m', '/p:Configuration=Release', "/p:Platform=$Platform", '/p:SignMode=Off')
Get-ChildItem -LiteralPath (Join-Path $sample "$Platform/Release/package")
