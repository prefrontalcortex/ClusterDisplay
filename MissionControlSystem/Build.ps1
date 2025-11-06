# Build.ps1
# Builds all projects in the MissionControlSystem solution in Release configuration

$ErrorActionPreference = "Stop"
$buildType = "Release"
$dotNetVersion = "net8.0"
$missionControlPath = $PSScriptRoot

Write-Host "Building MissionControlSystem in $buildType configuration..."
Write-Host "Using .NET version: $dotNetVersion"
Write-Host ""

function Build-Project($projectName, $projectPath) {
    Write-Host "Building $projectName..."
    $fullPath = Join-Path $missionControlPath $projectPath
    
    if (-not (Test-Path $fullPath)) {
        throw "Project file not found: $fullPath"
    }

    dotnet build $fullPath -c $buildType
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for $projectName"
    }
    Write-Host "Successfully built $projectName`n"
}

# Build projects in dependency order
try {
    # 1. Shared library (used by most other projects)
    Build-Project "MissionControl.Shared" "MissionControl.Shared/MissionControl.Shared.csproj"

    # 2. AssemblyRun (required by MissionControl)
    Build-Project "AssemblyRun" "AssemblyRun/AssemblyRun.csproj"

    # 3. MissionControl.Library
    Build-Project "MissionControl.Library" "MissionControl.Library/MissionControl.Library.csproj"

    # 4. Main applications
    Build-Project "HangarBay" "HangarBay/HangarBay.csproj"
    Build-Project "LaunchPad" "LaunchPad/LaunchPad.csproj"
    Build-Project "MissionControl" "MissionControl/MissionControl.csproj"

    # 5. Engineering UI (requires publishing)
    $uiServerPath = "MissionControl.EngineeringUI/Server/MissionControl.EngineeringUI.Server.csproj"
    Write-Host "Publishing Engineering UI..."
    dotnet publish (Join-Path $missionControlPath $uiServerPath) -c $buildType
    if ($LASTEXITCODE -ne 0) {
        throw "Publishing failed for Engineering UI"
    }
    Write-Host "Successfully published Engineering UI`n"

    # Run packaging script if present
    $packagingScript = Join-Path $missionControlPath "Package.ps1"
    if (Test-Path $packagingScript) {
        Write-Host "Running packaging script..."
        & $packagingScript
        if ($LASTEXITCODE -ne 0) {
            throw "Packaging failed"
        }
        Write-Host "Packaging completed successfully`n"
    }

    Write-Host "Build process completed successfully!"
    Write-Host "You can find the built binaries in the bin/$buildType/$dotNetVersion directories of each project"
    if (Test-Path $packagingScript) {
        Write-Host "Deployment packages are available in the root directory:"
        Write-Host "- HangarBay.zip"
        Write-Host "- LaunchPad.zip"
        Write-Host "- MissionControl.zip"
        Write-Host "- UI.zip"
    }

} catch {
    Write-Host "Build process failed: $_" -ForegroundColor Red
    exit 1
}