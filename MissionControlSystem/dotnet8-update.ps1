# Führe vorab einen Branch auf:
git checkout -b dotnet-update/net8

# 1) Liste der gefundenen .csproj (nur zur Kontrolle)
Get-ChildItem -Recurse -Filter *.csproj | Select-Object FullName

# 2) TargetFramework-Tags anpassen von net6.0 -> net8.0
Get-ChildItem -Recurse -Filter *.csproj | ForEach-Object {
    $path = $_.FullName
    $content = Get-Content $path -Raw
    $new = [regex]::Replace($content, '<TargetFramework>\s*net6.0\s*</TargetFramework>', '<TargetFramework>net8.0</TargetFramework>', 'IgnoreCase')
    if ($new -ne $content) {
        $new | Set-Content $path
        Write-Host "Updated TargetFramework in $path"
    }
}

# 3) Hartkodierte net6.0 in .csproj durch $(TargetFramework) ersetzen (vorsichtig)
Get-ChildItem -Recurse -Filter *.csproj | ForEach-Object {
    $path = $_.FullName
    $content = Get-Content $path -Raw
    $new = $content -replace '(\b)net6\.0(\b)', '$(TargetFramework)'
    if ($new -ne $content) {
        $new | Set-Content $path
        Write-Host "Replaced hardcoded net6.0 in $path"
    }
}

# 4) Änderungen prüfen, committen und pushen
git add -A
git commit -m "Retarget projects to .NET 8 and use $(TargetFramework) in PostBuilds"
#git push --set-upstream origin dotnet-update/net8g