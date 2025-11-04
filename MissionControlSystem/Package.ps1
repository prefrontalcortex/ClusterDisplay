# Package.ps1
# Ermittelt TargetFramework dynamisch aus MissionControl.csproj (Fallback net8.0)

$missionControlPath = $PSScriptRoot
$buildType = "Release"
$defaultFramework = "net8.0"

function Get-TargetFrameworkFromCsproj($csprojPath) {
    if (-not (Test-Path $csprojPath)) { return $null }
    $content = Get-Content $csprojPath -Raw
    $m = [regex]::Match($content, '<TargetFramework>\s*(?<tf>[^<\s]+)\s*</TargetFramework>', 'IgnoreCase')
    if ($m.Success) { return $m.Groups['tf'].Value.Trim() }
    return $null
}

# Suche MissionControl-Projekt (falls Pfad variiert)
$mcProj = Join-Path $missionControlPath "MissionControl\MissionControl.csproj"
$dotNetVersion = Get-TargetFrameworkFromCsproj $mcProj
if (-not $dotNetVersion) { $dotNetVersion = $defaultFramework }

Write-Host "Using target framework: $dotNetVersion"

$packagedFolder = Join-Path $PSScriptRoot "packaged"
if (-not (Test-Path $packagedFolder)) { New-Item $packagedFolder -ItemType Directory | Out-Null }

function Package-Folder($name, $srcRelative, $isPublish = $false, $exclude = @()) {
    $dstPath = [IO.Path]::Combine($packagedFolder, $name, "bin")
    if (-not (Test-Path $dstPath)) { New-Item $dstPath -ItemType Directory | Out-Null }

    if ($isPublish) {
        $srcPath = [IO.Path]::Combine($missionControlPath, $srcRelative, "bin", $buildType, $dotNetVersion, "publish")
    } else {
        $srcPath = [IO.Path]::Combine($missionControlPath, $srcRelative, "bin", $buildType, $dotNetVersion)
    }
    $copyPath = Join-Path $srcPath "*"
    Write-Host "Copying from $srcPath to $dstPath"
    Copy-Item -Path $copyPath -Destination $dstPath -Exclude $exclude -Recurse -ErrorAction Stop

    return $dstPath
}

# Package HangarBay
$hangarBayDstPath = Package-Folder "HangarBay" "HangarBay" $false @("appsettings.Development.json","HangarBay.deps.json")
Compress-Archive -Path (Join-Path $hangarBayDstPath "..") -DestinationPath "HangarBay.zip" -Force

# Package LaunchPad
$launchPadDstPath = Package-Folder "LaunchPad" "LaunchPad" $false @("appsettings.Development.json","LaunchPad.deps.json")
Compress-Archive -Path (Join-Path $launchPadDstPath "..") -DestinationPath "LaunchPad.zip" -Force

# Package MissionControl and dependencies
$missionControlDstPath = Package-Folder "MissionControl" "MissionControl" $false @("appsettings.Development.json","MissionControl.deps.json")
$dependenciesZipPath = Join-Path $missionControlDstPath ".."
Compress-Archive -Path (Join-Path $hangarBayDstPath "*") -DestinationPath (Join-Path $dependenciesZipPath "hangarBay.zip") -Force
Compress-Archive -Path (Join-Path $launchPadDstPath "*") -DestinationPath (Join-Path $dependenciesZipPath "launchPad.zip") -Force
if (Test-Path "MissionControl.zip") { Remove-Item "MissionControl.zip" -Force }
Compress-Archive -Path (Join-Path $missionControlDstPath "..") -DestinationPath "MissionControl.zip" -Force

# Package UI (publish expected) - falls publish fehlt, automatisch dotnet publish ausführen
$uiDstPath = [IO.Path]::Combine($packagedFolder, "UI")
if (-not (Test-Path $uiDstPath)) { New-Item $uiDstPath -ItemType Directory | Out-Null }

$uiProjRelative = "MissionControl.EngineeringUI\Server\MissionControl.EngineeringUI.Server.csproj"
$uiProjFullPath = [IO.Path]::Combine($missionControlPath, $uiProjRelative)
$uiSrcPath = [IO.Path]::Combine($missionControlPath, "MissionControl.EngineeringUI", "Server", "bin", $buildType, $dotNetVersion, "publish")

if (-not (Test-Path $uiSrcPath)) {
    Write-Host "UI publish folder not found: $uiSrcPath"
    Write-Host "Attempting 'dotnet publish' for the UI Server project..."
    if (-not (Test-Path $uiProjFullPath)) {
        throw "UI project file not found: $uiProjFullPath - bitte Pfad prüfen oder Projekt bauen."
    }

    $args = @("publish", $uiProjFullPath, "-c", $buildType, "-f", $dotNetVersion)
    $startInfo = @{
        FilePath = "dotnet"
        ArgumentList = $args
        NoNewWindow = $true
        Wait = $true
        RedirectStandardOutput = $false
        RedirectStandardError = $false
    }

    $proc = Start-Process @startInfo -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "dotnet publish failed for $uiProjFullPath (ExitCode $($proc.ExitCode))"
    }

    if (-not (Test-Path $uiSrcPath)) {
        throw "Publish scheinbar erfolgreich, aber Zielordner wurde nicht gefunden: $uiSrcPath"
    }
}

# Kopiere publizierte UI
Copy-Item -Path (Join-Path $uiSrcPath "*") -Destination $uiDstPath -Exclude "appsettings.Development.json" -Recurse -ErrorAction Stop

# optional: ignore missing compressed settings files without failing
Try { Remove-Item -Path ([IO.Path]::Combine($uiDstPath, "wwwroot", "appsettings.json.br")) -ErrorAction SilentlyContinue } Catch {}
Try { Remove-Item -Path ([IO.Path]::Combine($uiDstPath, "wwwroot", "appsettings.json.gz")) -ErrorAction SilentlyContinue } Catch {}

Compress-Archive -Path $uiDstPath -DestinationPath "UI.zip" -Force

# Cleanup temp directories
Remove-Item -Path $packagedFolder -Recurse -Force
Write-Host "Packaging complete."
