param(
    [string]$PackageDir,
    [string]$OutputDir,
    [string]$ProductVersion = "12.9.1",
    [string]$ProductName = "Engauge Digitizer",
    [string]$Manufacturer = "Le Xuan Thang / Engauge Open Source Developers"
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    return (Resolve-Path -LiteralPath $Path).Path
}

function Find-Tool([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $repoTool = Join-Path $script:RepoRoot "dist\wix314\$Name"
    if (Test-Path -LiteralPath $repoTool) {
        return $repoTool
    }

    $standardDirs = @(
        "WiX Toolset v3.14",
        "WiX Toolset v3.11"
    )
    foreach ($dir in $standardDirs) {
        $wixBin = Join-Path ${env:ProgramFiles(x86)} "$dir\bin\$Name"
        if (Test-Path -LiteralPath $wixBin) {
            return $wixBin
        }
    }

    throw "Cannot find $Name. Install WiX Toolset v3.14.1 or v3.11 and make sure $Name is available on PATH."
}

function Escape-Xml([string]$Value) {
    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-ShortHash([string]$Value) {
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha1.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").Substring(0, 10).ToLowerInvariant()
    } finally {
        $sha1.Dispose()
    }
}

function Get-SafeId([string]$Prefix, [string]$Value) {
    $clean = [regex]::Replace($Value, "[^A-Za-z0-9_\.]", "_")
    if ($clean.Length -eq 0 -or $clean[0] -match "[0-9]") {
        $clean = "x_$clean"
    }
    if ($clean.Length -gt 45) {
        $clean = $clean.Substring(0, 45)
    }
    return "{0}_{1}_{2}" -f $Prefix, $clean, (Get-ShortHash $Value)
}

function Get-RelativePath([string]$Root, [string]$Path) {
    $rootWithSlash = $Root.TrimEnd("\") + "\"
    return $Path.Substring($rootWithSlash.Length)
}

function Invoke-NativeTool([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Tool failed with exit code $LASTEXITCODE"
    }
}

function Write-PackageDirectory([string]$RelativeDir, [int]$Level) {
    $indent = " " * $Level
    $children = @($script:AllDirs | Where-Object {
        if ($RelativeDir -eq "") {
            $_ -notmatch "\\"
        } else {
            $_.StartsWith("$RelativeDir\") -and ($_.Substring($RelativeDir.Length + 1) -notmatch "\\")
        }
    })

    foreach ($file in @($script:FilesByDir[$RelativeDir] | Sort-Object RelativePath)) {
        $componentId = Get-SafeId "cmp" $file.RelativePath
        $fileId = Get-SafeId "fil" $file.RelativePath
        [void]$script:ComponentRefs.Add($componentId)
        [void]$script:XmlLines.Add(("{0}<Component Id=""{1}"" Guid=""*"" Win64=""yes"">" -f $indent, $componentId))
        [void]$script:XmlLines.Add(("{0}  <File Id=""{1}"" Source=""{2}"" KeyPath=""yes"" />" -f $indent, $fileId, (Escape-Xml $file.FullName)))
        [void]$script:XmlLines.Add(("{0}</Component>" -f $indent))
    }

    foreach ($child in ($children | Sort-Object)) {
        $name = Split-Path -Leaf $child
        $dirId = $script:DirectoryIds[$child]
        [void]$script:XmlLines.Add(("{0}<Directory Id=""{1}"" Name=""{2}"">" -f $indent, $dirId, (Escape-Xml $name)))
        Write-PackageDirectory $child ($Level + 2)
        [void]$script:XmlLines.Add(("{0}</Directory>" -f $indent))
    }
}

$repoRoot = Resolve-FullPath (Join-Path $PSScriptRoot "..\..")
$script:RepoRoot = $repoRoot
if (-not $PackageDir) {
    $PackageDir = Join-Path $repoRoot "dist\Engauge"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot "dist"
}

$packageRoot = Resolve-FullPath $PackageDir
$outputRoot = if (Test-Path -LiteralPath $OutputDir) {
    Resolve-FullPath $OutputDir
} else {
    (New-Item -ItemType Directory -Path $OutputDir -Force).FullName
}

$exePath = Join-Path $packageRoot "Engauge.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Cannot find $exePath. Run dev\windows\package_portable_msvc2022.bat first."
}

$iconPath = Join-Path $repoRoot "src\img\digitizer.ico"
if (-not (Test-Path -LiteralPath $iconPath)) {
    throw "Cannot find installer icon: $iconPath"
}

$candle = Find-Tool "candle.exe"
$light = Find-Tool "light.exe"
$workDir = Join-Path $outputRoot "msi"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$files = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
    $rel = Get-RelativePath $packageRoot $_.FullName
    [PSCustomObject]@{
        FullName = $_.FullName
        RelativePath = $rel
        RelativeDir = Split-Path -Parent $rel
    }
} | Sort-Object RelativePath)

$script:AllDirs = @($files |
    Where-Object { $_.RelativeDir } |
    ForEach-Object { $_.RelativeDir } |
    Sort-Object -Unique)

$script:DirectoryIds = @{}
foreach ($dir in $script:AllDirs) {
    $script:DirectoryIds[$dir] = Get-SafeId "dir" $dir
}

$script:FilesByDir = @{}
foreach ($file in $files) {
    if (-not $script:FilesByDir.ContainsKey($file.RelativeDir)) {
        $script:FilesByDir[$file.RelativeDir] = @()
    }
    $script:FilesByDir[$file.RelativeDir] += $file
}

$script:ComponentRefs = New-Object System.Collections.Generic.List[string]
$script:XmlLines = New-Object System.Collections.Generic.List[string]

$upgradeCode = "00A6792B-65ED-4894-A48B-B95D63C62CC6"
$msiPath = Join-Path $outputRoot ("Engauge-Digitizer-{0}-Windows-x64-Le-Xuan-Thang.msi" -f $ProductVersion)
$wxsPath = Join-Path $workDir "engauge_msvc2022_generated.wxs"
$wixObj = Join-Path $workDir "engauge_msvc2022_generated.wixobj"
$uiObj = Join-Path $workDir "WixUI_InstallDir_NoLicense.wixobj"

[void]$script:XmlLines.Add("<?xml version=""1.0"" encoding=""windows-1252""?>")
[void]$script:XmlLines.Add("<Wix xmlns=""http://schemas.microsoft.com/wix/2006/wi"">")
[void]$script:XmlLines.Add(("  <Product Id=""*"" Name=""{0}"" Language=""1033"" Version=""{1}"" Manufacturer=""{2}"" UpgradeCode=""{3}"">" -f (Escape-Xml $ProductName), (Escape-Xml $ProductVersion), (Escape-Xml $Manufacturer), $upgradeCode))
[void]$script:XmlLines.Add("    <Package InstallerVersion=""500"" Compressed=""yes"" InstallScope=""perMachine"" Platform=""x64"" />")
[void]$script:XmlLines.Add("    <MajorUpgrade DowngradeErrorMessage=""A newer version of Engauge Digitizer is already installed."" />")
[void]$script:XmlLines.Add("    <MediaTemplate EmbedCab=""yes"" />")
[void]$script:XmlLines.Add("    <Property Id=""ARPCONTACT"" Value=""Le Xuan Thang"" />")
[void]$script:XmlLines.Add(("    <Icon Id=""engauge.ico"" SourceFile=""{0}"" />" -f (Escape-Xml $iconPath)))
[void]$script:XmlLines.Add("    <Property Id=""ARPPRODUCTICON"" Value=""engauge.ico"" />")
[void]$script:XmlLines.Add("    <Directory Id=""TARGETDIR"" Name=""SourceDir"">")
[void]$script:XmlLines.Add("      <Directory Id=""ProgramFiles64Folder"">")
[void]$script:XmlLines.Add("        <Directory Id=""INSTALLFOLDER"" Name=""Engauge Digitizer"">")
Write-PackageDirectory "" 10
[void]$script:XmlLines.Add("        </Directory>")
[void]$script:XmlLines.Add("      </Directory>")
[void]$script:XmlLines.Add("      <Directory Id=""ProgramMenuFolder"">")
[void]$script:XmlLines.Add("        <Directory Id=""ProgramMenuDir"" Name=""Engauge Digitizer"" />")
[void]$script:XmlLines.Add("      </Directory>")
[void]$script:XmlLines.Add("      <Directory Id=""DesktopFolder"" />")
[void]$script:XmlLines.Add("    </Directory>")

[void]$script:ComponentRefs.Add("cmp_StartMenuShortcut")
[void]$script:XmlLines.Add("    <DirectoryRef Id=""ProgramMenuDir"">")
[void]$script:XmlLines.Add("      <Component Id=""cmp_StartMenuShortcut"" Guid=""*"" Win64=""yes"">")
[void]$script:XmlLines.Add("        <Shortcut Id=""StartMenuShortcut"" Name=""Engauge Digitizer"" Description=""Launch Engauge Digitizer"" Target=""[INSTALLFOLDER]Engauge.exe"" WorkingDirectory=""INSTALLFOLDER"" Icon=""engauge.ico"" />")
[void]$script:XmlLines.Add("        <RemoveFolder Id=""ProgramMenuDir"" On=""uninstall"" />")
[void]$script:XmlLines.Add("        <RegistryValue Root=""HKCU"" Key=""Software\Engauge Digitizer"" Name=""StartMenuShortcut"" Type=""integer"" Value=""1"" KeyPath=""yes"" />")
[void]$script:XmlLines.Add("      </Component>")
[void]$script:XmlLines.Add("    </DirectoryRef>")

[void]$script:ComponentRefs.Add("cmp_DesktopShortcut")
[void]$script:XmlLines.Add("    <DirectoryRef Id=""DesktopFolder"">")
[void]$script:XmlLines.Add("      <Component Id=""cmp_DesktopShortcut"" Guid=""*"" Win64=""yes"">")
[void]$script:XmlLines.Add("        <Shortcut Id=""DesktopShortcut"" Name=""Engauge Digitizer"" Description=""Launch Engauge Digitizer"" Target=""[INSTALLFOLDER]Engauge.exe"" WorkingDirectory=""INSTALLFOLDER"" Icon=""engauge.ico"" />")
[void]$script:XmlLines.Add("        <RegistryValue Root=""HKCU"" Key=""Software\Engauge Digitizer"" Name=""DesktopShortcut"" Type=""integer"" Value=""1"" KeyPath=""yes"" />")
[void]$script:XmlLines.Add("      </Component>")
[void]$script:XmlLines.Add("    </DirectoryRef>")

[void]$script:XmlLines.Add("    <Feature Id=""Complete"" Title=""Engauge Digitizer"" Level=""1"">")
foreach ($componentId in ($script:ComponentRefs | Sort-Object -Unique)) {
    [void]$script:XmlLines.Add(("      <ComponentRef Id=""{0}"" />" -f $componentId))
}
[void]$script:XmlLines.Add("    </Feature>")
[void]$script:XmlLines.Add("    <Property Id=""WIXUI_INSTALLDIR"" Value=""INSTALLFOLDER"" />")
[void]$script:XmlLines.Add("    <UIRef Id=""WixUI_InstallDir_NoLicense"" />")
[void]$script:XmlLines.Add("  </Product>")
[void]$script:XmlLines.Add("</Wix>")

Set-Content -LiteralPath $wxsPath -Value $script:XmlLines -Encoding UTF8

Invoke-NativeTool $candle @("-nologo", "-out", $wixObj, $wxsPath)
Invoke-NativeTool $candle @("-nologo", "-out", $uiObj, (Join-Path $repoRoot "dev\windows\WixUI_InstallDir_NoLicense.wxs"))
Invoke-NativeTool $light @("-nologo", "-sval", "-ext", "WixUIExtension", "-out", $msiPath, $wixObj, $uiObj)

Write-Host "Created MSI: $msiPath"
