using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace HookshotBuilder;

/// (fork: github.com/roblesleo/Hookshot, branch full) This builder builds the fork: AMD FSR 4 with its model row, NVIDIA DLSS,
/// the Insert menu in 13 languages. It keeps the official builder's tools (the parts the latest official release lists in
/// hookshot-setup.txt, each checked against its SHA-256) and builds the fork's code with them: before each build,
/// Montar-Hookshot-worker.ps1 (inside this app) fetches the tools once, the fork's code anew, AMD's FSR runtime and, with
/// DLSS ticked, NVIDIA's SDK, into %LOCALAPPDATA%\HookshotFSR, and lays src\ out as the official tools folder. Nothing of the
/// game is downloaded. Its settings, build files and SDKs are its own, apart from the official builder's.
static class Fork
{
    public static readonly bool On = true;
    public const string Repo = "github.com/roblesleo/Hookshot";
    // (LOCALAPPDATA as the environment has it, as the worker reads it: a test can point both at an empty folder)
    public static string Home => Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") is { Length: > 0 } l ? l
        : Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HookshotFSR");
    /// The fork's code with the tools linked in (the worker's output): what Tools.Find() builds from
    public static string Src => Path.Combine(Home, "src");
    public static string FfxSdk => Path.Combine(Home, "ffx-sdk");

    /// The worker, written out of this app's resources beside the rest (a fresh copy each time: this app's own)
    static string Worker()
    {
        Directory.CreateDirectory(Home);
        var path = Path.Combine(Home, "Montar-Hookshot-worker.ps1");
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("HookshotBuilder.Montar-Hookshot-worker.ps1")
                      ?? throw new InvalidOperationException("the worker is missing from this app");
        using (var f = File.Create(path)) s.CopyTo(f);
        return path;
    }

    /// The tools, the fork's code and AMD's (and NVIDIA's) files, each line as it comes. null when done, else why not
    public static Task<string?> Prepare(bool dlss, Action<string> line, CancellationToken token)
    {
        return Task.Run(async () =>
        {
            string worker;
            try { worker = Worker(); }
            catch (Exception e) { return e.Message; }
            var si = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            si.Environment.Remove("PSModulePath");   // (Windows PowerShell's own modules, not PowerShell 7's when started from it)
            foreach (var a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", worker, "-Nup", "none", "-Out", "none", "-ToolsOnly" })
                si.ArgumentList.Add(a);
            if (dlss) si.ArgumentList.Add("-Dlss");
            string? error = null;
            using var p = new Process { StartInfo = si };
            p.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                if (e.Data.StartsWith("@@error ")) error = e.Data[8..];
                else if (e.Data.StartsWith("@@stage ")) line(e.Data[8..]);
                else if (!e.Data.StartsWith("@@")) line(e.Data);
            };
            p.ErrorDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) line(e.Data); };
            try { p.Start(); }
            catch (Exception e) { return "PowerShell could not start: " + e.Message; }
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            try { await p.WaitForExitAsync(token); }
            catch (OperationCanceledException)
            {
                try { p.Kill(entireProcessTree: true); } catch (Exception) { }
                return "Cancelled";
            }
            p.WaitForExit();
            return p.ExitCode == 0 ? null : error ?? $"the preparation stopped (code {p.ExitCode})";
        }, CancellationToken.None);
    }

    public const string FsrLicense =
        "AMD FSR 4 is AMD's, not Hookshot's. With it ticked, the build downloads AMD's FSR runtime for Vulkan (FSR SDK v2.4.0: " +
        "amd_fidelityfx_loader_vk.dll and amd_fidelityfx_upscaler_vk.dll, signed by AMD) from github.com/GPUOpen-LibrariesAndSDKs/" +
        "FidelityFX-SDK, each file checked against its SHA-256, under AMD's FSR SDK license:\n\n" +
        "https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/blob/7539ae8b6568ad29ed78a753404351daf3b5cca7/Kits/FidelityFX/docs/license.md\n\n" +
        "The license is saved beside the files (LICENSE-AMD-FSR-SDK.md), in the game folder.\n\nDownload AMD's files?";
}
