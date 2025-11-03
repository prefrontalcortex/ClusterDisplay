$missionControlPath = $PSScriptRoot
$buildType = "Release"
$dotNetVersion = "net8.0"

$packagedFolder = Join-Path $PSScriptRoot "packaged"
if (-not (Test-Path $packagedFolder))
{
    New-Item $packagedFolder -ItemType Directory | Out-Null
}

#Package HangarBay
$hangarBayDstPath = [IO.Path]::Combine($packagedFolder, "HangarBay", "bin")
if (-not (Test-Path $hangarBayDstPath))
{
    New-Item $hangarBayDstPath -ItemType Directory | Out-Null
}
$hangarBaySrcPath = [IO.Path]::Combine($missionControlPath, "HangarBay", "bin", $buildType, $dotNetVersion)
$copyPath = Join-Path $hangarBaySrcPath "*"
Copy-Item -Path $copyPath -Destination $hangarBayDstPath -Exclude "appsettings.Development.json", "HangarBay.deps.json" -ErrorAction Stop

$toZipPath = Join-Path $hangarBayDstPath ".."
$zipPath = "HangarBay.zip"
Compress-Archive -Path $toZipPath -DestinationPath $zipPath -Force

#Package LaunchPad
$launchPadDstPath = [IO.Path]::Combine($packagedFolder, "LaunchPad", "bin")
if (-not (Test-Path $launchPadDstPath))
{
    New-Item $launchPadDstPath -ItemType Directory | Out-Null
}
$launchPadSrcPath = [IO.Path]::Combine($missionControlPath, "LaunchPad", "bin", $buildType, $dotNetVersion)
$copyPath = Join-Path $launchPadSrcPath "*"
Copy-Item -Path $copyPath -Destination $launchPadDstPath -Exclude "appsettings.Development.json", "LaunchPad.deps.json" -ErrorAction Stop

$toZipPath = Join-Path $launchPadDstPath ".."
$zipPath = "LaunchPad.zip"
Compress-Archive -Path $toZipPath -DestinationPath $zipPath -Force

#Package MissionControl
$missionControlDstPath = [IO.Path]::Combine($packagedFolder, "MissionControl", "bin")
if (-not (Test-Path $missionControlDstPath))
{
    New-Item $missionControlDstPath -ItemType Directory | Out-Null
}
$missionControlSrcPath = [IO.Path]::Combine($missionControlPath, "MissionControl", "bin", $buildType, $dotNetVersion)
$copyPath = Join-Path $missionControlSrcPath "*"
Copy-Item -Path $copyPath -Destination $missionControlDstPath -Exclude "appsettings.Development.json", "MissionControl.deps.json" -ErrorAction Stop

$dependenciesZipPath = Join-Path $missionControlDstPath ".."
Compress-Archive -Path (Join-Path $hangarBayDstPath "*") -DestinationPath (Join-Path $dependenciesZipPath "hangarBay.zip") -Force
Compress-Archive -Path (Join-Path $launchPadDstPath "*") -DestinationPath (Join-Path $dependenciesZipPath "launchPad.zip") -Force

$toZipPath = Join-Path $missionControlDstPath ".."
$zipPath = "MissionControl.zip"
if (Test-Path $zipPath)
{
    Remove-Item $zipPath -Force
}
Compress-Archive -Path $toZipPath -DestinationPath $zipPath -Force

#Package UI
$uiDstPath = [IO.Path]::Combine($packagedFolder, "UI")
if (-not (Test-Path $uiDstPath))
{
    New-Item $uiDstPath -ItemType Directory | Out-Null
}
$uiSrcPath = [IO.Path]::Combine($missionControlPath, "MissionControl.EngineeringUI", "Server", "bin", $buildType, $dotNetVersion, "publish")
$copyPath = Join-Path $uiSrcPath "*"
Copy-Item -Path $copyPath -Destination $uiDstPath -Exclude "appsettings.Development.json" -Recurse -ErrorAction Stop

# optional: ignore missing compressed settings files without failing
Try { Remove-Item -Path ([IO.Path]::Combine($uiDstPath, "wwwroot", "appsettings.json.br")) -ErrorAction SilentlyContinue } Catch {}
Try { Remove-Item -Path ([IO.Path]::Combine($uiDstPath, "wwwroot", "appsettings.json.gz")) -ErrorAction SilentlyContinue } Catch {}

$toZipPath = $uiDstPath
$zipPath = "UI.zip"
Compress-Archive -Path $toZipPath -DestinationPath $zipPath -Force

# Cleanup temp directories
Remove-Item -Path $packagedFolder -Recurse -Force