<#
  Update-Addons.ps1 - install Davis's WoW addons and keep them "up to date" after game patches.

  What it does:
    1. Reads the game's version from its .exe (e.g. 1.60.1) and works out the addon interface number (16001).
    2. If any addon's .toc has an older interface number, updates it (this is what fixes "Out of date").
    3. Runs the offline tests, if Lua is installed.
    4. Copies every addon into the game's Interface\AddOns folder.

  Run it from PowerShell:
    .\Update-Addons.ps1                          # WoW Forever beta (default)
    .\Update-Addons.ps1 -Game "_forever_"        # a different game folder, e.g. after the full launch
    .\Update-Addons.ps1 -SkipTests
  Then restart the game (or /reload if every addon was already installed).
#>
param(
  [string]$Game = "_classic_beta_",
  [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft",
  [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$gameDir = Join-Path $WowRoot $Game
$addonsDir = Join-Path $gameDir "Interface\AddOns"
# NeedIt is its own repo (github.com/daviscouch/NeedIt) - clone it into this folder to include it
$addons = @("NeedIt", "HunterHelper", "TalentGuide", "TidyVendor", "CraftProfit") |
  Where-Object { Test-Path (Join-Path $here $_) }

if (-not (Test-Path $gameDir)) { throw "Game folder not found: $gameDir" }

# 1. Interface number from the game's exe version: 1.60.1 -> 16001
$exe = Get-ChildItem $gameDir -Filter "Wow*.exe" | Where-Object { $_.Name -notmatch "Error" } | Select-Object -First 1
if (-not $exe) { throw "No Wow*.exe in $gameDir" }
$v = [version]$exe.VersionInfo.FileVersion
$interface = $v.Major * 10000 + $v.Minor * 100 + $v.Build
Write-Host "Game: $($exe.Name) version $($v.Major).$($v.Minor).$($v.Build) -> interface $interface"

# 2. Bring every .toc up to that interface number
foreach ($a in $addons) {
  foreach ($toc in Get-ChildItem (Join-Path $here $a) -Filter "*.toc") {
    $text = [IO.File]::ReadAllText($toc.FullName)
    if ($text -match "## Interface:\s*(\d+)") {
      $old = [int]$Matches[1]
      if ($old -ne $interface) {
        $text = $text -replace "## Interface:\s*\d+", "## Interface: $interface"
        [IO.File]::WriteAllText($toc.FullName, $text)
        Write-Host "  $a\$($toc.Name): interface $old -> $interface"
      }
    }
  }
}

# 3. Offline tests
$lua = Get-Command lua -ErrorAction SilentlyContinue
if (-not $lua) { $lua = Get-Item "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe" -ErrorAction SilentlyContinue }
if (-not $SkipTests -and $lua) {
  $luaPath = if ($lua.Source) { $lua.Source } else { $lua.FullName }
  $failed = $false
  Push-Location $here
  foreach ($t in Get-ChildItem "tests" -Filter "test_*.lua") {
    $out = & $luaPath $t.FullName 2>&1 | Select-Object -Last 1
    Write-Host ("  tests\" + $t.Name + ": " + $out)
    if ($LASTEXITCODE -ne 0) { $failed = $true }
  }
  Pop-Location
  if ($addons -contains "NeedIt") {
    Push-Location (Join-Path $here "NeedIt")
    $out = & $luaPath "tests\test_needit.lua" "NeedIt.lua" 2>&1 | Select-Object -Last 1
    Write-Host ("  NeedIt\tests\test_needit.lua: " + $out)
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Pop-Location
  }
  if ($failed) { throw "Some tests failed - nothing was installed." }
} elseif (-not $SkipTests) {
  Write-Host "  (Lua not installed - skipping tests)"
}

# 4. Install: only the files the game loads (.toc, .lua, .xml, .tga), not tests or READMEs
New-Item -ItemType Directory -Force $addonsDir | Out-Null
$new = @()
foreach ($a in $addons) {
  $dest = Join-Path $addonsDir $a
  if (-not (Test-Path $dest)) { $new += $a; New-Item -ItemType Directory -Force $dest | Out-Null }
  Get-ChildItem (Join-Path $here $a) -File | Where-Object { $_.Extension -in ".toc", ".lua", ".xml", ".tga" } |
    ForEach-Object { Copy-Item $_.FullName $dest -Force }
}
Write-Host "Installed $($addons.Count) addons into $addonsDir"
if ($new.Count -gt 0) {
  Write-Host "New addons ($($new -join ', ')): restart the game to load them."
} else {
  Write-Host "In game: /reload (restart instead if the interface number changed)."
}
