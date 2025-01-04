# Script that builds libpff
#
# Version: 20230411

Param (
	[string]$Configuration = ${Env:Configuration},
	[string]$Platform = ${Env:Platform},
	[string]$PlatformToolset = "",
	[string]$PythonPath = "C:\Python311",
	[string]$VisualStudioVersion = "",
	[string]$VSToolsOptions = "--extend-with-x64",
	[string]$VSToolsPath = "..\vstools"
)

$ExitSuccess = 0
$ExitFailure = 1

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$paths = @()
$paths += Join-Path -Path $scriptPath -ChildPath ".venv/Scripts"
$paths += @("${PythonPath}")
$paths += $env:PATH -split [System.IO.Path]::PathSeparator

$Python = $null
foreach ($path in $paths) {
    $PythonBase = Join-Path -Path $path -ChildPath "python"
    foreach ($executablePath in @($PythonBase, "$PythonBase.exe")) {
        if (Test-Path -Path $executablePath -PathType Leaf) {
            $Python = $executablePath
            Write-Output "Found Python executable: ${Python}"

            # Get executable root path
            $PythonRoot = Split-Path -Parent $Python

            # If there is a 'activate.ps1' in the same folder as the Python executable, go ahead and run it now.
            $activateScript = Join-Path -Path $PythonRoot -ChildPath "activate.ps1"
            if (Test-Path -Path $activateScript -PathType Leaf) {
                . $activateScript
                Write-Output "Activated environment: ${activateScript}"
            }

            break
        }
    }
    if ($null -ne $Python) {
        $Python = $executablePath
        Write-Output "Found Python executable: ${Python}"

        # Get executable root path
        $PythonRoot = Split-Path -Parent $Python

        # If there is a 'activate.ps1' in the same folder as the Python executable, go ahead and run it now.
        $activateScript = Join-Path -Path $PythonRoot -ChildPath "activate.ps1"
        if (Test-Path -Path $activateScript -PathType Leaf) {
            . $activateScript
            Write-Output "Activated environment: ${activateScript}"
        }

        break
    }
}

$Git = "git"
$GitUrl = "https://github.com/libyal/vstools.git"

$MSVSCppConvert = "${VSToolsPath}\scripts\msvscpp-convert.py"

If (-Not (Test-Path $Python)) {
    Write-Host "Missing Python: ${Python}" -foreground Red

    Exit ${ExitFailure}
}
If (-Not (Test-Path ${VSToolsPath})) {
    # PowerShell will raise NativeCommandError if git writes to stdout or stderr
    # therefore 2>&1 is added and the output is stored in a variable.
    $Output = Invoke-Expression -Command "${Git} clone ${GitUrl} ${VSToolsPath} 2>&1" | % { "$_" }
}
Else {
    Push-Location "${VSToolsPath}"

    Try {
        # Make sure vstools are up to date.
        $Output = Invoke-Expression -Command "${Git} pull 2>&1" | % { "$_" }
    }
    Finally {
        Pop-Location
    }
}
If (-Not (Test-Path ${MSVSCppConvert})) {
    Write-Host "Missing msvscpp-convert.py: ${MSVSCppConvert}" -foreground Red

    Exit ${ExitFailure}
}
If (-Not ${VisualStudioVersion}) {
    $VisualStudioVersion = "2022"

    Write-Host "Visual Studio version not set defaulting to: ${VisualStudioVersion}" -foreground Red
}
If ((${VisualStudioVersion} -ne "2008") -And (${VisualStudioVersion} -ne "2010") -And (${VisualStudioVersion} -ne "2012") -And (${VisualStudioVersion} -ne "2013") -And (${VisualStudioVersion} -ne "2015") -And (${VisualStudioVersion} -ne "2017") -And (${VisualStudioVersion} -ne "2019") -And (${VisualStudioVersion} -ne "2022")) {
    Write-Host "Unsupported Visual Studio version: ${VisualStudioVersion}" -foreground Red

    Exit ${ExitFailure}
}
$MSBuild = ""

If (${VisualStudioVersion} -eq "2008") {
    $MSBuild = "C:\Windows\Microsoft.NET\Framework\v3.5\MSBuild.exe"
}
ElseIf ((${VisualStudioVersion} -eq "2010") -Or (${VisualStudioVersion} -eq "2012")) {
    $MSBuild = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
}
ElseIf (${VisualStudioVersion} -eq "2013") {
    $MSBuild = "C:\Program Files (x86)\MSBuild\12.0\Bin\MSBuild.exe"
}
ElseIf (${VisualStudioVersion} -eq "2015") {
    $MSBuild = "C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe"
}
ElseIf (${VisualStudioVersion} -eq "2017") {
    $Results = Get-ChildItem -Path "C:\Program Files\Microsoft Visual Studio\${VisualStudioVersion}\*\MSBuild\15.0\Bin\MSBuild.exe" -Recurse -ErrorAction SilentlyContinue -Force

    If ($Results.Count -eq 0) {
        $Results = Get-ChildItem -Path "C:\Program Files (x86)\Microsoft Visual Studio\${VisualStudioVersion}\*\MSBuild\15.0\Bin\MSBuild.exe" -Recurse -ErrorAction SilentlyContinue -Force
    }
    If ($Results.Count -gt 0) {
        $MSBuild = $Results[0].FullName
    }
}
ElseIf (${VisualStudioVersion} -eq "2019" -Or ${VisualStudioVersion} -eq "2022") {
    $Results = Get-ChildItem -Path "C:\Program Files\Microsoft Visual Studio\${VisualStudioVersion}\*\MSBuild\Current\Bin\MSBuild.exe" -Recurse -ErrorAction SilentlyContinue -Force

    If ($Results.Count -eq 0) {
        $Results = Get-ChildItem -Path "C:\Program Files (x86)\Microsoft Visual Studio\${VisualStudioVersion}\*\MSBuild\Current\Bin\MSBuild.exe" -Recurse -ErrorAction SilentlyContinue -Force
    }
    If ($Results.Count -gt 0) {
        $MSBuild = $Results[0].FullName
    }
}
If (-Not ${MSBuild}) {
    Write-Host "Unable to determine path to msbuild.exe" -foreground Red

    Exit ${ExitFailure}
}
ElseIf (-Not (Test-Path ${MSBuild})) {
    Write-Host "Missing msbuild.exe: ${MSBuild}" -foreground Red

    Exit ${ExitFailure}
}

If (${VisualStudioVersion} -eq "2008") {
    $VSSolutionPath = "msvscpp"
}
Else {
    $VSSolutionPath = "vs${VisualStudioVersion}"

    If (-Not (Test-Path "${VSSolutionPath}")) {
        ${Env:PYTHONPATH} = ${VSToolsPath}

        Invoke-Expression -Command "& '${Python}' ${MSVSCppConvert} --output-format ${VisualStudioVersion} ${VSToolsOptions} msvscpp\libpff.sln 2>&1" | % { "$_" }
    }
}
$VSSolutionFile = "${VSSolutionPath}\libpff.sln"

If (-Not (Test-Path "${VSSolutionFile}")) {
    Write-Host "Missing Visual Studio ${VisualStudioVersion} solution file: ${VSSolutionFile}" -foreground Red

    Exit ${ExitFailure}
}
If ([string]::IsNullOrWhiteSpace(${Configuration})) {
    $Configuration = "Release"

    Write-Host "Configuration not set defaulting to: ${Configuration}"
}
If ([string]::IsNullOrWhiteSpace(${Platform})) {
    $Platform = "x64"

    Write-Host "Platform not set defaulting to: ${Platform}"
}
$PlatformToolset = ""

If (-Not ${PlatformToolset}) {
    If (${VisualStudioVersion} -eq "2015") {
        $PlatformToolset = "v140"
    }
    ElseIf (${VisualStudioVersion} -eq "2017") {
        $PlatformToolset = "v141"
    }
    ElseIf (${VisualStudioVersion} -eq "2019") {
        $PlatformToolset = "v142"
    }
    ElseIf (${VisualStudioVersion} -eq "2022") {
        $PlatformToolset = "v143"
    }
    Write-Host "PlatformToolset not set defaulting to: ${PlatformToolset}"
}
$MSBuildOptions = "/verbosity:quiet /target:Build /property:Configuration=${Configuration},Platform=${Platform}"

If (${PlatformToolset}) {
    $MSBuildOptions = "${MSBuildOptions} /property:PlatformToolset=${PlatformToolset}"
}
Write-Output "##[cmd] '${MSBuild}' ${MSBuildOptions} ${VSSolutionFile}"
If (${Env:APPVEYOR} -eq "True") {
    Invoke-Expression -Command "& '${MSBuild}' ${MSBuildOptions} ${VSSolutionFile} /logger:'C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll' 2>&1" | % { "$_" }
}
Else {
    Invoke-Expression -Command "& '${MSBuild}' ${MSBuildOptions} ${VSSolutionFile} 2>&1" | % { "$_" }
}
if ($?) {
    Exit ${ExitSuccess}
}
if (LASTEXITCODE -ne 0) {
    Exit ${LASTEXITCODE}
}
Exit ${ExitFailure}
