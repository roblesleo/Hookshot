# The work of Montar-Hookshot.ps1 (the window), in a process of its own so the window stays responsive. It writes its
# progress as lines on stdout: "@@stage <text>", "@@progress <0..1>", "@@error <text>", "@@done <folder>", and the build's
# own lines between them.
#
# 1. The official Hookshot Builder's tools (Python, llvm-mingw, the Vulkan headers, the prebuilt files), as the official
#    setup gets them: the parts its latest release lists in hookshot-setup.txt, each checked against its SHA-256. Only
#    what a command-line build needs (not the builder's window or emsdk). Kept between builds.
# 2. This fork's code (github.com/roblesleo/Hookshot, branch full).
# 3. nx2/make_game.py: the game from the player's own .nup, with AMD FSR 4 (AMD's runtime fetched from AMD, SHA-256
#    checked), and NVIDIA DLSS when asked (NVIDIA's SDK fetched under NVIDIA's license, which the window showed).
param(
    [Parameter(Mandatory = $true)][string]$Nup,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Language = 'pt-BR',
    [switch]$Dlss,
    [switch]$ToolsOnly   # (a test: the tools and the code fetched, no build)
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)   # (the window reads this output as UTF-8)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Repo = 'roblesleo/Hookshot'
$Branch = 'full'
$Home2 = Join-Path $env:LOCALAPPDATA 'HookshotFSR'
New-Item -ItemType Directory -Force $Home2 | Out-Null

function Say($t) { [Console]::Out.WriteLine($t); [Console]::Out.Flush() }
function Fail($t) { Say ("@@error " + $t); exit 1 }

function Get-File($url, $path, $sha, $size) {
    if ((Test-Path $path) -and $sha -and ((Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -eq $sha)) { return }
    for ($try = 1; $try -le 3; $try++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile ($path + '.part')
            if ($sha -and ((Get-FileHash ($path + '.part') -Algorithm SHA256).Hash.ToLower() -ne $sha)) {
                Remove-Item ($path + '.part') -Force
                throw "o arquivo baixado não é o esperado (SHA-256)"
            }
            Move-Item -Force ($path + '.part') $path
            return
        } catch {
            if ($try -eq 3) { throw }
            Say ("  (tentando de novo: " + $_.Exception.Message + ")")
        }
    }
}

try {
    # ---- 1. the official builder's tools ----
    Say "@@stage Baixando as ferramentas do Hookshot Builder oficial"
    $raw = (Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/NotRexed/Hookshot/releases/latest/download/hookshot-setup.txt').Content
    $list = if ($raw -is [byte[]]) { [Text.Encoding]::UTF8.GetString($raw) } else { [string]$raw }   # (served as bytes)
    $tag = (($list -split "`n") | Where-Object { $_ -like 'tag *' } | Select-Object -First 1) -replace '^tag\s+', ''
    $tag = $tag.Trim()
    if (-not $tag) { Fail "a lista de ferramentas do Hookshot não pôde ser lida" }
    $root = Join-Path $Home2 ("tools-" + $tag)
    $tools = Join-Path $root 'HookshotBuilder\tools'
    $dl = Join-Path $Home2 'downloads'
    New-Item -ItemType Directory -Force $dl | Out-Null
    $want = @('-app-', '-python-', '-cpm-', '-third_party-', '-wgpu-native-', 'llvm-mingw')
    $parts = @()
    foreach ($line in ($list -split "`n")) {
        $f = $line.Trim() -split '\s+'
        if ($f.Count -lt 7 -or $f[0] -ne 'part') { continue }
        $url = $f[6]
        if (-not ($want | Where-Object { $url -like ('*' + $_ + '*') })) { continue }
        $parts += [pscustomobject]@{ Sha = $f[1].ToLower(); Size = [int64]$f[2]; Dest = $f[3]; Inner = $f[4]; Rename = $f[5]; Url = $url }
    }
    if ($parts.Count -lt $want.Count) { Fail "a lista de ferramentas do Hookshot não tem todas as partes esperadas" }
    $ready = Join-Path $root '.ready'
    if (-not (Test-Path $ready)) {
        $i = 0
        foreach ($p in $parts) {
            $i++
            $name = Split-Path $p.Url -Leaf
            Say ("  " + $name + " (" + [math]::Round($p.Size / 1MB) + " MB)")
            Say ("@@progress " + ([string][math]::Round(0.02 + 0.10 * $i / $parts.Count, 3)).Replace(',', '.'))
            $zip = Join-Path $dl $name
            Get-File $p.Url $zip $p.Sha $p.Size
            $dest = if ($p.Dest -eq '.') { $root } else { Join-Path $root $p.Dest }
            New-Item -ItemType Directory -Force $dest | Out-Null
            if ($p.Inner -ne '-') {   # (a zip of another project: its folder renamed into place, as the official setup does)
                $tmp = Join-Path $Home2 'unzip'
                if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
                [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
                $target = Join-Path $dest $p.Rename
                if (Test-Path $target) { Remove-Item $target -Recurse -Force }
                Move-Item (Join-Path $tmp $p.Inner) $target
                Remove-Item $tmp -Recurse -Force
            } else {
                $z = [IO.Compression.ZipFile]::OpenRead($zip)
                try {
                    foreach ($e in $z.Entries) {
                        $to = Join-Path $dest $e.FullName
                        if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force $to | Out-Null; continue }
                        New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
                        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $to, $true)
                    }
                } finally { $z.Dispose() }
            }
        }
        New-Item -ItemType File -Force $ready | Out-Null
    }
    foreach ($need in @('python\python.exe', 'llvm-mingw\bin\clang.exe', 'cpm', 'wgpu-native', 'third_party', 'work')) {
        if (-not (Test-Path (Join-Path $tools $need))) { Fail ("as ferramentas baixadas não têm " + $need) }
    }
    Say ("  ferramentas do Hookshot " + $tag + " em " + $tools)

    # ---- 2. this fork's code ----
    Say ("@@stage Baixando o código (github.com/" + $Repo + ", " + $Branch + ")")
    Say "@@progress 0.13"
    $src = Join-Path $Home2 'src'
    $zip = Join-Path $Home2 'src.zip'
    Get-File "https://github.com/$Repo/archive/refs/heads/$Branch.zip" $zip $null 0
    if (Test-Path $src) { Remove-Item $src -Recurse -Force }
    $tmp = Join-Path $Home2 'unzip'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $src
    Remove-Item $tmp -Recurse -Force
    # (what a clone lacks and the tools carry: the prebuilt files under third_party\ and the work files)
    $tp = Join-Path $tools 'third_party'
    Get-ChildItem $tp -Recurse -File -Include *.dll, *.exe, *.lib, *.sha1 | ForEach-Object {
        $dst = Join-Path (Join-Path $src 'third_party') $_.FullName.Substring($tp.Length + 1)
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
    }
    New-Item -ItemType Directory -Force (Join-Path $src 'work') | Out-Null
    Copy-Item (Join-Path $tools 'work\*') (Join-Path $src 'work') -Recurse -Force

    if ($ToolsOnly) { Say ("@@done ferramentas em " + $tools + ", código em " + $src); exit 0 }

    # ---- 3. the build ----
    $env:RX_CPM = Join-Path $tools 'cpm'
    $env:WGPU_NATIVE = Join-Path $tools 'wgpu-native'
    $env:HOOKSHOT_MINGW = Join-Path $tools 'llvm-mingw'
    $env:HOOKSHOT_FFX_SDK = Join-Path $Home2 'ffx-sdk'
    $a = @('-I', 'nx2\make_game.py', '--nup', $Nup, '--out', $Out, '--language', $Language,
           '--work', (Join-Path $Home2 'work'), '--fsr', '--fetch-fsr-runtime')
    if ($Dlss) {
        $env:HOOKSHOT_NGX_SDK = Join-Path $Home2 'ngx-sdk'
        $a += @('--fetch-ngx-sdk', '--accept-nvidia-license')
    } else {
        Remove-Item Env:HOOKSHOT_NGX_SDK -ErrorAction SilentlyContinue
    }
    Set-Location $src
    & (Join-Path $tools 'python\python.exe') @a 2>&1 | ForEach-Object {
        $l = [string]$_
        if ($l -match '^@@progress ([0-9.]+)') { $l = "@@progress " + ([string][math]::Round(0.15 + 0.85 * [double]$Matches[1], 3)).Replace(',', '.') }
        Say $l
    }
    if ($LASTEXITCODE -ne 0) { Fail ("a montagem parou (código " + $LASTEXITCODE + ")") }
    Say ("@@done " + $Out)
} catch {
    Fail $_.Exception.Message
}
