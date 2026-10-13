param(
  [Parameter(Mandatory = $true)][string]$DevEcoRoot,
  [string]$JavaRoot = '',
  [string]$Device = '',
  [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOutput = Join-Path $PSScriptRoot '.test-results'
function Find-TaskTool([string[]]$relativePaths) {
  foreach ($relativePath in $relativePaths) {
    $candidate = Join-Path $DevEcoRoot $relativePath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  throw ('Tool not found under ' + $DevEcoRoot + ': ' + ($relativePaths -join ', '))
}
function Get-TaskApi([string]$version) {
  if ($version -match '\((\d+)\)$') { return [int]$Matches[1] }
  if ($version -match '^(\d+)(?:\.|$)') { return [int]$Matches[1] }
  throw ('Unsupported SDK version: ' + $version)
}
$taskNode = Find-TaskTool @('tools/node/node.exe', 'tool/node/node.exe')
$taskHvigor = Find-TaskTool @('tools/hvigor/bin/hvigorw.js', 'hvigor/bin/hvigorw.js')
$taskHdc = Join-Path $DevEcoRoot 'sdk/default/openharmony/toolchains/hdc.exe'
$taskSdkMetadataPath = Join-Path $DevEcoRoot 'sdk/default/sdk-pkg.json'
$taskSdkMetadata = (Get-Content -Raw -LiteralPath $taskSdkMetadataPath | ConvertFrom-Json).data
$taskSdkApi = Get-TaskApi ([string]$taskSdkMetadata.apiVersion)
$taskProfile = Get-Content -Raw -LiteralPath (Join-Path $taskRoot 'build-profile.json5')
$taskTargetMatch = [regex]::Match($taskProfile, '"targetSdkVersion"\s*:\s*"([^"]+)"')
$taskCompatibleMatch = [regex]::Match($taskProfile, '"compatibleSdkVersion"\s*:\s*"([^"]+)"')
if (!$taskTargetMatch.Success -or !$taskCompatibleMatch.Success) { throw 'Project SDK configuration missing' }
$taskTargetApi = Get-TaskApi $taskTargetMatch.Groups[1].Value
$taskCompatibleApi = Get-TaskApi $taskCompatibleMatch.Groups[1].Value
if ($taskSdkApi -lt $taskTargetApi) {
  throw "Project targets API $taskTargetApi, but this toolchain contains API $taskSdkApi. Use a matching DevEco Studio or Command Line Tools SDK."
}
$taskJavaRoot = $JavaRoot
if ($taskJavaRoot -eq '') { $taskJavaRoot = Join-Path $DevEcoRoot 'jbr' }
if (!(Test-Path -LiteralPath (Join-Path $taskJavaRoot 'bin/java.exe') -PathType Leaf)) {
  throw 'A JDK is required. Pass -JavaRoot when using Command Line Tools without a bundled jbr.'
}
foreach ($toolPath in @($taskNode, $taskHvigor, $taskHdc)) {
  if (!(Test-Path -LiteralPath $toolPath)) { throw "DevEco tool missing: $toolPath" }
}
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
Write-Output ('SDK: ' + $taskSdkMetadata.displayName + ' / ' + $taskSdkMetadata.version + ' (API ' + $taskSdkApi + ')')
$taskOldPath = $env:PATH
$taskOldSdk = $env:DEVECO_SDK_HOME
$taskOldJava = $env:JAVA_HOME
$taskOldNode = $env:NODE_HOME
Push-Location $taskRoot
try {
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
  $env:JAVA_HOME = $taskJavaRoot
  $env:NODE_HOME = Split-Path -Parent $taskNode
  $env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:NODE_HOME + ';' + $taskOldPath
  foreach ($target in @('default', 'ohosTest')) {
    $log = Join-Path $taskOutput "$target-build.log"
    & $taskNode $taskHvigor --mode module -p product=default -p "module=entry@$target" assembleHap --no-daemon --info *> $log
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 35; throw "$target build failed" }
    Write-Output "PASS DevEco build: $target"
  }
  if (!$BuildOnly) {
    if ($Device -eq '') { throw 'Choose an emulator/device from hdc list targets and pass -Device.' }
    $taskDeviceApiOutput = (& $taskHdc -t $Device shell param get const.ohos.apiversion 2>&1) -join "`n"
    if ($taskDeviceApiOutput.Trim() -notmatch '^\d+$') { throw 'Cannot verify the target device API version' }
    $taskDeviceApi = [int]$taskDeviceApiOutput.Trim()
    if ($taskDeviceApi -lt $taskCompatibleApi) {
      throw "Device API $taskDeviceApi is below minimum API $taskCompatibleApi. Choose a compatible device; no package was installed."
    }
    foreach ($target in @('default', 'ohosTest')) {
      $package = Get-ChildItem -LiteralPath "entry/build/default/outputs/$target" -Filter '*.hap' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($null -eq $package) { throw "No $target HAP was built" }
      $installed = & $taskHdc -t $Device install $package.FullName 2>&1
      $installed | Set-Content -LiteralPath (Join-Path $taskOutput "$target-install.log")
      if (($installed -join "`n") -notmatch 'install bundle successfully') { throw "$target install failed: $installed" }
    }
    # Keep editor focus tests separate from tests that activate the real EntryAbility.
    foreach ($testGroup in @(
      @{ Name = 'editor'; Classes = 'ActsAbilityTest,FlowTextRegression'; Log = 'device-tests.log' },
      @{ Name = 'window'; Classes = 'WindowChromeRegression'; Log = 'window-tests.log' }
    )) {
      $testLog = Join-Path $taskOutput $testGroup.Log
      & $taskHdc -t $Device shell aa force-stop com.chungu.weaver | Out-Null
      & $taskHdc -t $Device shell aa test -b com.chungu.weaver -m entry_test -s unittest OpenHarmonyTestRunner -s class $testGroup.Classes -s timeout 20000 -w 60 *> $testLog
      $result = Get-Content -Raw -LiteralPath $testLog
      # aa can exit 0 even when Hypium reports errors; inspect the actual test summary.
      if ($result -notmatch 'Tests run: ([1-9]\d*), Failure: 0, Error: 0, Pass: ([1-9]\d*), Ignore: 0' -or $Matches[1] -ne $Matches[2]) {
        Get-Content -LiteralPath $testLog -Tail 30
        throw ($testGroup.Name + ' device regression failed; inspect ' + $testGroup.Log)
      }
      Write-Output ($testGroup.Name + ': ' + $Matches[0])
    }
  }
  Write-Output "Logs: $taskOutput"
} finally {
  Pop-Location
  $env:PATH = $taskOldPath
  $env:DEVECO_SDK_HOME = $taskOldSdk
  $env:JAVA_HOME = $taskOldJava
  $env:NODE_HOME = $taskOldNode
}
