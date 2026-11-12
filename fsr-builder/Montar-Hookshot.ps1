# Montar Hookshot: a window that builds this fork of Hookshot (AMD FSR 4 with its model choice, NVIDIA DLSS, the menu in
# 13 languages) from the player's own copy of the game. Nothing else to install first: Montar-Hookshot-worker.ps1 fetches
# the official Hookshot Builder's tools as its setup does (SHA-256 checked), this fork's code, AMD's FSR runtime and, when
# ticked, NVIDIA's DLSS SDK, then builds. Nothing of the game is downloaded: the game is the player's own .nup. Never
# share the game folder this makes: it holds the game.
#
# Run it with Montar-Hookshot.bat beside it (PowerShell 5.1, as Windows has it).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Home2 = Join-Path $env:LOCALAPPDATA 'HookshotFSR'
New-Item -ItemType Directory -Force $Home2 | Out-Null
$Worker = Join-Path $PSScriptRoot 'Montar-Hookshot-worker.ps1'

function Find-Nups {
    $found = @()
    foreach ($d in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents")) {
        # (-Filter *.nup also matches .nupkg, as Windows' own filter does: the extension is checked exactly)
        if (Test-Path -LiteralPath $d) { $found += Get-ChildItem $d -Filter *.nup -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ieq '.nup' } }
    }
    return $found | Sort-Object LastWriteTime -Descending
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Montar Hookshot (FSR 4, DLSS, 13 idiomas)'
$form.Size = New-Object Drawing.Size(740, 600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

function Add-Label($text, $top) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point(12, $top); $l.AutoSize = $true
    $form.Controls.Add($l); return $l
}

$y = 12
Add-Label '1. Seu jogo (o .nup da SUA cópia, versão suportada pelo Hookshot):' $y | Out-Null
$y += 24
$nup = New-Object Windows.Forms.ComboBox
$nup.Location = New-Object Drawing.Point(12, $y); $nup.Size = New-Object Drawing.Size(580, 28)
foreach ($f in Find-Nups) { [void]$nup.Items.Add($f.FullName) }
if ($nup.Items.Count) { $nup.SelectedIndex = 0 }
$form.Controls.Add($nup)
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Procurar...'; $browse.Location = New-Object Drawing.Point(600, ($y - 1)); $browse.Size = New-Object Drawing.Size(110, 30)
$browse.Add_Click({
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Filter = 'Pacote do jogo (*.nup)|*.nup'
    if ($d.ShowDialog() -eq 'OK') { [void]$nup.Items.Add($d.FileName); $nup.SelectedItem = $d.FileName }
})
$form.Controls.Add($browse)

$y += 40
Add-Label '2. Instalar o jogo em:' $y | Out-Null
$y += 24
$out = New-Object Windows.Forms.TextBox
$out.Location = New-Object Drawing.Point(12, $y); $out.Size = New-Object Drawing.Size(580, 28)
$out.Text = Join-Path $env:USERPROFILE 'Games\Hookshot-FSR'
$form.Controls.Add($out)
$pick = New-Object Windows.Forms.Button
$pick.Text = 'Mudar...'; $pick.Location = New-Object Drawing.Point(600, ($y - 1)); $pick.Size = New-Object Drawing.Size(110, 30)
$pick.Add_Click({
    $d = New-Object Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq 'OK') { $out.Text = Join-Path $d.SelectedPath 'Hookshot-FSR' }
})
$form.Controls.Add($pick)

$y += 40
Add-Label '3. Idioma do jogo:' $y | Out-Null
$lang = New-Object Windows.Forms.ComboBox
$lang.DropDownStyle = 'DropDownList'
$lang.Location = New-Object Drawing.Point(150, ($y - 3)); $lang.Size = New-Object Drawing.Size(300, 28)
$Languages = @(
    @('pt-BR', 'Português (Brasil)'), @('en-US', 'English (US)'), @('en-GB', 'English (UK)'),
    @('es-419', 'Español (Latinoamérica)'), @('es', 'Español (España)'), @('fr', 'Français (France)'),
    @('fr-CA', 'Français (Canada)'), @('de', 'Deutsch'), @('it', 'Italiano'), @('nl', 'Nederlands'), @('pl', 'Polski'),
    @('ru', 'Русский'), @('ja', '日本語'), @('ko', '한국어'), @('zh-Hans', '简体中文'), @('zh-Hant', '繁體中文'))
foreach ($l in $Languages) { [void]$lang.Items.Add($l[1]) }
$lang.SelectedIndex = 0
$form.Controls.Add($lang)

$dlss = New-Object Windows.Forms.CheckBox
$dlss.Text = '4. NVIDIA DLSS também (só placas NVIDIA RTX; baixa o SDK da NVIDIA sob a licença da NVIDIA)'
$dlss.Location = New-Object Drawing.Point(12, ($y + 32)); $dlss.AutoSize = $true
$dlss.Add_Click({
    if ($dlss.Checked) {
        $msg = "O NVIDIA DLSS é da NVIDIA. Marcando, a montagem baixa o DLSS SDK (v310.9.16) de github.com/NVIDIA/DLSS sob a licença da NVIDIA:`n`nhttps://github.com/NVIDIA/DLSS/blob/9981c6350dc58c0ce21f024fd65e31e851c31689/LICENSE.txt`n`nOs arquivos ficam só neste PC. Nunca compartilhe uma pasta de jogo montada com eles. Aceita a licença da NVIDIA?"
        if ([Windows.Forms.MessageBox]::Show($msg, 'NVIDIA DLSS', 'YesNo', 'Information') -ne 'Yes') { $dlss.Checked = $false }
    }
})
$form.Controls.Add($dlss)

$y += 70
$bar = New-Object Windows.Forms.ProgressBar
$bar.Location = New-Object Drawing.Point(12, $y); $bar.Size = New-Object Drawing.Size(698, 22); $bar.Maximum = 1000
$form.Controls.Add($bar)
$y += 28
$stage = Add-Label 'Pronto. Baixa uns 300 MB de ferramentas na primeira vez, leva de 20 a 45 minutos e precisa de uns 60 GB livres.' $y
$y += 26
$log = New-Object Windows.Forms.TextBox
$log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.ReadOnly = $true; $log.Font = New-Object Drawing.Font('Consolas', 9)
$log.Location = New-Object Drawing.Point(12, $y); $log.Size = New-Object Drawing.Size(698, 170)
$form.Controls.Add($log)
$y += 180
$go = New-Object Windows.Forms.Button
$go.Text = 'Montar o jogo'; $go.Location = New-Object Drawing.Point(560, $y); $go.Size = New-Object Drawing.Size(150, 36)
$form.Controls.Add($go)
$play = New-Object Windows.Forms.Button
$play.Text = 'Jogar'; $play.Location = New-Object Drawing.Point(400, $y); $play.Size = New-Object Drawing.Size(150, 36); $play.Enabled = $false
$form.Controls.Add($play)

function Say($text) { $log.AppendText($text + "`r`n") }

$script:proc = $null
$script:outFile = Join-Path $Home2 'montar-saida.txt'
$script:readAt = 0
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 400
$timer.Add_Tick({
    if (Test-Path -LiteralPath $script:outFile) {
        try {
            $fs = [IO.File]::Open($script:outFile, 'Open', 'Read', 'ReadWrite')
            $fs.Seek($script:readAt, 'Begin') | Out-Null
            $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd()
            $script:readAt = $fs.Position
            $sr.Close()
        } catch { $text = '' }
        foreach ($line in ($text -split "`r?`n")) {
            if (-not $line) { continue }
            if ($line -match '^@@progress ([0-9.]+)') { $bar.Value = [Math]::Min(1000, [int]([double]$Matches[1] * 1000)); continue }
            if ($line -match '^@@stage \S+ (.*)') { $stage.Text = $Matches[1]; Say ('== ' + $Matches[1]); continue }
            if ($line -match '^@@stage (.*)') { $stage.Text = $Matches[1]; Say ('== ' + $Matches[1]); continue }
            if ($line -match '^@@error (.*)') { $stage.Text = 'Erro: ' + $Matches[1]; Say ('ERRO: ' + $Matches[1]); continue }
            if ($line -match '^@@done') { $bar.Value = 1000; $stage.Text = 'Pronto! O jogo está em ' + $out.Text; $play.Enabled = $true; continue }
            if ($line -match '^@@') { continue }
            Say $line
        }
    }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $go.Enabled = $true
        $err = Join-Path $Home2 'montar-erros.txt'
        if ($script:proc.ExitCode -ne 0 -and (Test-Path -LiteralPath $err)) { Get-Content $err -Tail 15 | ForEach-Object { Say $_ } }
    }
})

$play.Add_Click({
    $exe = Join-Path $out.Text 'hookshot.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $out.Text 'bin\hookshot.exe' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) }
})

$go.Add_Click({
    if (-not $nup.Text -or -not (Test-Path -LiteralPath $nup.Text)) {
        [Windows.Forms.MessageBox]::Show('Escolha o .nup do seu jogo.', 'Falta o jogo') | Out-Null
        return
    }
    $go.Enabled = $false
    $play.Enabled = $false
    $log.Clear()
    $bar.Value = 0
    Remove-Item $script:outFile, (Join-Path $Home2 'montar-erros.txt') -ErrorAction SilentlyContinue
    $script:readAt = 0
    $q = { param($s) '"' + $s + '"' }
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $q $Worker), '-Nup', (& $q $nup.Text), '-Out', (& $q $out.Text),
               '-Language', $Languages[$lang.SelectedIndex][0])
    if ($dlss.Checked) { $args2 += '-Dlss' }
    # (AMD FSR 4 is AMD's: its runtime is fetched only with AMD's license accepted; without it the game is built with FSR 4
    # and the player puts AMD's DLLs there)
    $amd = "O AMD FSR 4 é da AMD. A montagem baixa o runtime do FSR para Vulkan (FSR SDK v2.4.0: amd_fidelityfx_loader_vk.dll e amd_fidelityfx_upscaler_vk.dll, assinados pela AMD) de github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK sob a licença do FSR SDK da AMD:`n`nhttps://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/7539ae8b6568ad29ed78a753404351daf3b5cca7/Kits/FidelityFX/docs/license.md`n`nAceita a licença da AMD?"
    if ([Windows.Forms.MessageBox]::Show($amd, 'AMD FSR 4', 'YesNo', 'Information') -eq 'Yes') { $args2 += '-AcceptAmdLicense' }
    $script:proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $script:outFile -RedirectStandardError (Join-Path $Home2 'montar-erros.txt')
    $stage.Text = 'Começando...'
    $timer.Start()
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) {
        if ([Windows.Forms.MessageBox]::Show('A montagem ainda está rodando. Parar e fechar?', 'Montar Hookshot', 'YesNo') -ne 'Yes') { $_.Cancel = $true; return }
        try { & taskkill.exe /T /F /PID $script:proc.Id | Out-Null } catch {}
    }
})

[void]$form.ShowDialog()
