# Montar Hookshot com AMD FSR: a small window that builds Hookshot from this fork (roblesleo/Hookshot, branch fsr) with
# AMD FSR 4 / FSR 3.1 in the Upscaler row, from the player's own copy of the game.
#
# It needs the official Hookshot Builder installed once (github.com/NotRexed/Hookshot/releases/latest): its tools folder
# (the compiler, Python, Vulkan headers) is what builds the game. Nothing of the game is downloaded: the game files are the
# player's own .nup (or romfs and exefs). AMD's FSR runtime comes from AMD's repository (scripts/ffx_sdk.py), NVIDIA's DLSS
# SDK from NVIDIA's (only when ticked, under NVIDIA's license). Never share the game folder this makes.
#
# Run it with Montar-Hookshot-FSR.bat beside it (PowerShell 5.1, as Windows has it).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo   = 'roblesleo/Hookshot'
$Branch = 'fsr'
$Home2  = Join-Path $env:LOCALAPPDATA 'HookshotFSR'

function Find-Tools {
    $versions = Join-Path $env:LOCALAPPDATA 'HookshotBuilder\versions'
    $cur = Join-Path $versions 'current.txt'
    if (Test-Path $cur) {
        $v = (Get-Content $cur -Raw).Trim()
        $t = Join-Path $versions "$v\HookshotBuilder\tools"
        if (Test-Path (Join-Path $t 'python\python.exe')) { return $t }
    }
    if (Test-Path $versions) {
        foreach ($d in Get-ChildItem $versions -Directory | Sort-Object LastWriteTime -Descending) {
            $t = Join-Path $d.FullName 'HookshotBuilder\tools'
            if (Test-Path (Join-Path $t 'python\python.exe')) { return $t }
        }
    }
    return $null
}

function Find-Nups {
    $found = @()
    foreach ($d in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents")) {
        if (Test-Path $d) { $found += Get-ChildItem $d -Filter *.nup -File -ErrorAction SilentlyContinue }
    }
    return $found
}

# ---- the window ----
$form = New-Object Windows.Forms.Form
$form.Text = 'Montar Hookshot com AMD FSR'
$form.Size = New-Object Drawing.Size(720, 560)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$y = 12
function Add-Label($text, $top) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point(12, $top); $l.AutoSize = $true
    $form.Controls.Add($l); return $l
}

Add-Label 'Seu jogo (.nup da sua cópia, versão suportada pelo Hookshot):' $y | Out-Null
$y += 24
$nup = New-Object Windows.Forms.ComboBox
$nup.Location = New-Object Drawing.Point(12, $y); $nup.Size = New-Object Drawing.Size(560, 28)
foreach ($f in Find-Nups) { [void]$nup.Items.Add($f.FullName) }
if ($nup.Items.Count) { $nup.SelectedIndex = 0 }
$form.Controls.Add($nup)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Procurar...'; $browse.Location = New-Object Drawing.Point(580, ($y - 1)); $browse.Size = New-Object Drawing.Size(110, 30)
$browse.Add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Filter = 'Pacote do jogo (*.nup)|*.nup'
    if ($d.ShowDialog() -eq 'OK') { [void]$nup.Items.Add($d.FileName); $nup.SelectedItem = $d.FileName }
})
$form.Controls.Add($browse)

$y += 40
Add-Label 'Instalar o jogo em:' $y | Out-Null
$y += 24
$out = New-Object Windows.Forms.TextBox
$out.Location = New-Object Drawing.Point(12, $y); $out.Size = New-Object Drawing.Size(560, 28)
$out.Text = Join-Path $env:USERPROFILE 'Games\Hookshot-FSR'
$form.Controls.Add($out)
$pick = New-Object Windows.Forms.Button
$pick.Text = 'Mudar...'; $pick.Location = New-Object Drawing.Point(580, ($y - 1)); $pick.Size = New-Object Drawing.Size(110, 30)
$pick.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq 'OK') { $out.Text = Join-Path $d.SelectedPath 'Hookshot-FSR' }
})
$form.Controls.Add($pick)

$y += 40
Add-Label 'Idioma do jogo:' $y | Out-Null
$lang = New-Object Windows.Forms.ComboBox
$lang.DropDownStyle = 'DropDownList'
$lang.Location = New-Object Drawing.Point(140, ($y - 3)); $lang.Size = New-Object Drawing.Size(300, 28)
# (the game's languages, as nx2/make_game.py LANGUAGES has them: code and name)
$Languages = @(
    @('pt-BR', 'Português (Brasil)'), @('en-US', 'Inglês (EUA)'), @('en-GB', 'Inglês (Reino Unido)'),
    @('es-419', 'Espanhol (América Latina)'), @('es', 'Espanhol (Espanha)'), @('fr', 'Francês (França)'),
    @('fr-CA', 'Francês (Canadá)'), @('de', 'Alemão'), @('it', 'Italiano'), @('nl', 'Holandês'), @('pl', 'Polonês'),
    @('ru', 'Russo'), @('ja', 'Japonês'), @('ko', 'Coreano'), @('zh-Hans', 'Chinês (simplificado)'),
    @('zh-Hant', 'Chinês (tradicional)'))
foreach ($l in $Languages) { [void]$lang.Items.Add($l[1] + '  (' + $l[0] + ')') }
$lang.SelectedIndex = 0
$form.Controls.Add($lang)

$dlss = New-Object Windows.Forms.CheckBox
$dlss.Text = 'NVIDIA DLSS também (placas RTX; baixa o SDK da NVIDIA sob a licença da NVIDIA)'
$dlss.Location = New-Object Drawing.Point(12, ($y + 30)); $dlss.AutoSize = $true
$dlss.Add_Click({
    if ($dlss.Checked) {
        $msg = "O NVIDIA DLSS é da NVIDIA. Marcando, a montagem baixa o DLSS SDK (v310.9.16) de github.com/NVIDIA/DLSS sob a licença da NVIDIA:`n`nhttps://github.com/NVIDIA/DLSS/blob/9981c6350dc58c0ce21f024fd65e31e851c31689/LICENSE.txt`n`nOs arquivos ficam só neste PC. Nunca compartilhe uma pasta de jogo montada com eles. Aceita a licença da NVIDIA?"
        if ([Windows.Forms.MessageBox]::Show($msg, 'NVIDIA DLSS', 'YesNo', 'Information') -ne 'Yes') { $dlss.Checked = $false }
    }
})
$form.Controls.Add($dlss)

$y += 66
$bar = New-Object Windows.Forms.ProgressBar
$bar.Location = New-Object Drawing.Point(12, $y); $bar.Size = New-Object Drawing.Size(678, 22); $bar.Maximum = 1000
$form.Controls.Add($bar)
$y += 28
$stage = Add-Label 'Pronto para montar. Leva de 20 a 45 minutos e precisa de uns 60 GB livres.' $y
$y += 26
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true; $log.Font = New-Object Drawing.Font('Consolas', 9)
$log.Location = New-Object Drawing.Point(12, $y); $log.Size = New-Object Drawing.Size(678, 150)
$form.Controls.Add($log)
$y += 160
$go = New-Object Windows.Forms.Button
$go.Text = 'Montar o jogo'; $go.Location = New-Object Drawing.Point(540, $y); $go.Size = New-Object Drawing.Size(150, 36)
$form.Controls.Add($go)
$play = New-Object Windows.Forms.Button
$play.Text = 'Jogar'; $play.Location = New-Object Drawing.Point(380, $y); $play.Size = New-Object Drawing.Size(150, 36)
$play.Enabled = $false
$form.Controls.Add($play)

function Say($text) { $log.AppendText($text + "`r`n"); [Windows.Forms.Application]::DoEvents() }

# ---- the build ----
$script:proc = $null
$script:outFile = $null
$script:readAt = 0
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500

$timer.Add_Tick({
    if (-not $script:outFile -or -not (Test-Path $script:outFile)) { return }
    try {
        $fs = [IO.File]::Open($script:outFile, 'Open', 'Read', 'ReadWrite')
        $fs.Seek($script:readAt, 'Begin') | Out-Null
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        $script:readAt = $fs.Position
        $sr.Close()
    } catch { return }
    foreach ($line in ($text -split "`r?`n")) {
        if (-not $line) { continue }
        if ($line -match '^@@progress ([0-9.]+)') { $bar.Value = [Math]::Min(1000, [int]([double]$Matches[1] * 1000)); continue }
        if ($line -match '^@@stage \S+ (.*)') { $stage.Text = $Matches[1]; Say ("== " + $Matches[1]); continue }
        if ($line -match '^@@done') { continue }
        if ($line -match '^@@error (.*)') { $stage.Text = 'Erro: ' + $Matches[1]; Say ('ERRO: ' + $Matches[1]); continue }
        if ($line -match '^@@') { continue }
        Say $line
    }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $go.Enabled = $true
        if ($script:proc.ExitCode -eq 0) {
            $bar.Value = 1000
            $stage.Text = 'Pronto! O jogo está em ' + $out.Text
            $play.Enabled = $true
        } else {
            $errFile = Join-Path $Home2 'build-errors.txt'
            if (Test-Path $errFile) { Get-Content $errFile -Tail 15 | ForEach-Object { Say $_ } }
            if ($stage.Text -notlike 'Erro*') { $stage.Text = 'A montagem parou (código ' + $script:proc.ExitCode + '). Veja o texto acima.' }
        }
    }
})

$play.Add_Click({
    $exe = Join-Path $out.Text 'hookshot.exe'
    if (Test-Path $exe) { Start-Process -FilePath $exe -WorkingDirectory $out.Text }
})

$go.Add_Click({
    $go.Enabled = $false
    $log.Clear()
    try {
        $tools = Find-Tools
        if (-not $tools) {
            [Windows.Forms.MessageBox]::Show("Instale primeiro o Hookshot Builder oficial (ele traz o compilador e as ferramentas). Vou abrir a página.", 'Falta o Hookshot Builder') | Out-Null
            Start-Process 'https://github.com/NotRexed/Hookshot/releases/latest'
            $go.Enabled = $true; return
        }
        if (-not $nup.Text -or -not (Test-Path $nup.Text)) {
            [Windows.Forms.MessageBox]::Show('Escolha o .nup do seu jogo.', 'Falta o jogo') | Out-Null
            $go.Enabled = $true; return
        }
        Say ("Ferramentas do Hookshot Builder: " + $tools)

        # this fork's code, the branch with AMD FSR
        $src = Join-Path $Home2 'src'
        $zip = Join-Path $Home2 'src.zip'
        New-Item -ItemType Directory -Force $Home2 | Out-Null
        $stage.Text = 'Baixando o código (github.com/' + $Repo + ', ' + $Branch + ')'
        Say $stage.Text
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip
        if (Test-Path $src) { Remove-Item $src -Recurse -Force }
        $tmp = Join-Path $Home2 'unzip'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        Move-Item (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName $src
        Remove-Item $tmp -Recurse -Force

        # what a clone lacks and the builder's tools carry: the prebuilt files under third_party\ and the work files
        Say 'Copiando as ferramentas que o código precisa...'
        $tp = Join-Path $tools 'third_party'
        Get-ChildItem $tp -Recurse -File -Include *.dll, *.exe, *.lib, *.sha1 | ForEach-Object {
            $rel = $_.FullName.Substring($tp.Length + 1)
            $dst = Join-Path (Join-Path $src 'third_party') $rel
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
        }
        $tw = Join-Path $tools 'work'
        if (Test-Path $tw) {
            New-Item -ItemType Directory -Force (Join-Path $src 'work') | Out-Null
            Copy-Item (Join-Path $tw '*') (Join-Path $src 'work') -Recurse -Force
        }

        $env:RX_CPM = Join-Path $tools 'cpm'
        $env:WGPU_NATIVE = Join-Path $tools 'wgpu-native'
        $env:HOOKSHOT_MINGW = Join-Path $tools 'llvm-mingw'
        $env:HOOKSHOT_FFX_SDK = Join-Path $Home2 'ffx-sdk'
        $margs = @('-I', 'nx2\make_game.py', '--nup', $nup.Text, '--out', $out.Text, '--language', $Languages[$lang.SelectedIndex][0],
                  '--work', (Join-Path $Home2 'work'), '--fetch-ffx-sdk')
        if ($dlss.Checked) {
            $env:HOOKSHOT_NGX_SDK = Join-Path $Home2 'ngx-sdk'
            $margs += @('--fetch-ngx-sdk', '--accept-nvidia-license')
        } else {
            Remove-Item Env:HOOKSHOT_NGX_SDK -ErrorAction SilentlyContinue
        }
        $script:outFile = Join-Path $Home2 'build-output.txt'
        $errFile = Join-Path $Home2 'build-errors.txt'
        Remove-Item $script:outFile, $errFile -ErrorAction SilentlyContinue
        $script:readAt = 0
        $quoted = $margs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
        $stage.Text = 'Montando...'
        $script:proc = Start-Process -FilePath (Join-Path $tools 'python\python.exe') -ArgumentList $quoted -WorkingDirectory $src `
            -RedirectStandardOutput $script:outFile -RedirectStandardError $errFile -NoNewWindow -PassThru
        $timer.Start()
    } catch {
        Say ('ERRO: ' + $_.Exception.Message)
        $stage.Text = 'Erro: ' + $_.Exception.Message
        $go.Enabled = $true
    }
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) {
        if ([Windows.Forms.MessageBox]::Show('A montagem ainda está rodando. Parar e fechar?', 'Montar Hookshot', 'YesNo') -ne 'Yes') { $_.Cancel = $true; return }
        try { Stop-Process -Id $script:proc.Id -Force } catch {}
    }
})

[void]$form.ShowDialog()
