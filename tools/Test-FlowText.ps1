param(
  [Parameter(Mandatory = $true)][string]$DevEcoRoot,
  [string]$Device = '',
  [switch]$BuildOnly
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOutput = Join-Path $PSScriptRoot '.test-results'
$taskNode = Join-Path $DevEcoRoot 'tools/node/node.exe'
$taskHvigor = Join-Path $DevEcoRoot 'tools/hvigor/bin/hvigorw.js'
$taskHdc = Join-Path $DevEcoRoot 'sdk/default/openharmony/toolchains/hdc.exe'
foreach ($toolPath in @($taskNode, $taskHvigor, $taskHdc)) {
  if (!(Test-Path -LiteralPath $toolPath)) { throw "DevEco tool missing: $toolPath" }
}
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskOldPath = $env:PATH
$taskOldSdk = $env:DEVECO_SDK_HOME
$taskOldJava = $env:JAVA_HOME
$taskOldNode = $env:NODE_HOME
Push-Location $taskRoot
try {
  $env:DEVECO_SDK_HOME = Join-Path $DevEcoRoot 'sdk'
  $env:JAVA_HOME = Join-Path $DevEcoRoot 'jbr'
  $env:NODE_HOME = Join-Path $DevEcoRoot 'tools/node'
  $env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:NODE_HOME + ';' + $taskOldPath
  foreach ($target in @('default', 'ohosTest')) {
    $log = Join-Path $taskOutput "$target-build.log"
    & $taskNode $taskHvigor --mode module -p product=default -p "module=entry@$target" assembleHap --no-daemon --info *> $log
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 35; throw "$target build failed" }
    Write-Output "PASS DevEco build: $target"
  }
  if (!$BuildOnly) {
    if ($Device -eq '') { throw 'Choose an emulator/device from hdc list targets and pass -Device.' }
    foreach ($target in @('default', 'ohosTest')) {
      $package = Get-ChildItem -LiteralPath "entry/build/default/outputs/$target" -Filter '*.hap' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($null -eq $package) { throw "No $target HAP was built" }
      $installed = & $taskHdc -t $Device install $package.FullName 2>&1
      $installed | Set-Content -LiteralPath (Join-Path $taskOutput "$target-install.log")
      if (($installed -join "`n") -notmatch 'install bundle successfully') { throw "$target install failed: $installed" }
    }
    $testLog = Join-Path $taskOutput 'device-tests.log'
    & $taskHdc -t $Device shell aa test -b com.chungu.weaver -m entry_test -s unittest OpenHarmonyTestRunner -w 60 *> $testLog
    $result = Get-Content -Raw -LiteralPath $testLog
    # aa can exit 0 even when Hypium reports errors; inspect the actual test summary.
    if ($result -notmatch 'Tests run: [1-9]\d*, Failure: 0, Error: 0, Pass: [1-9]\d*, Ignore: 0') {
      Get-Content -LiteralPath $testLog -Tail 30
      throw 'FlowText device regression failed; inspect device-tests.log'
    }
    Write-Output ($Matches[0])
  }
  Write-Output "Logs: $taskOutput"
} finally {
  Pop-Location
  $env:PATH = $taskOldPath
  $env:DEVECO_SDK_HOME = $taskOldSdk
  $env:JAVA_HOME = $taskOldJava
  $env:NODE_HOME = $taskOldNode
}
