# Script that synchronizes the local test data
#
# Version: 20230709

$TestSet = "public"
$TestInputDirectory = "tests/input"
$TestFiles = "outlook.pst"

If (-Not (Test-Path ${TestInputDirectory}))
{
	New-Item -Name ${TestInputDirectory} -ItemType "directory" | Out-Null
}
If (-Not (Test-Path "${TestInputDirectory}\${TestSet}"))
{
	New-Item -Name "${TestInputDirectory}\${TestSet}" -ItemType "directory" | Out-Null
}
ForEach ($TestFile in ${TestFiles} -split " ")
{
	$Url = "https://github.com/log2timeline/plaso/blob/main/test_data/${TestFile}?raw=true"

    try {
        Invoke-WebRequest -Uri ${Url} -OutFile "${TestInputDirectory}\${TestSet}\${TestFile}" -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Output "Download failed: ${Url}"
    }
}
