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

    // ---- the branch's commit: the code a game folder was built from, against the branch's newest (Update when it moved on) ----
    const string Branch = "full";
    const string BuiltFile = ".hookshot_fork_commit";

    /// The commit a game folder was built from (Mark), or null: built before the folders kept it, or not by this builder
    public static string? Built(string folder)
    {
        try
        {
            var path = Path.Combine(folder, BuiltFile);
            return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
        }
        catch (Exception) { return null; }
    }

    /// After a build: the commit of the code it built (the worker's src\.fork_commit) kept in the game folder
    public static void Mark(string folder)
    {
        try
        {
            var code = Path.Combine(Src, ".fork_commit");
            if (Directory.Exists(folder) && File.Exists(code)) File.Copy(code, Path.Combine(folder, BuiltFile), overwrite: true);
        }
        catch (Exception) { }
    }

    /// The branch's newest commit on GitHub, quietly (null: GitHub did not answer)
    public static async Task<string?> Head()
    {
        try
        {
            using var http = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("HookshotBuilder");
            http.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github.sha");
            var sha = (await http.GetStringAsync($"https://api.github.com/repos/{Repo["github.com/".Length..]}/commits/{Branch}")).Trim();
            return System.Text.RegularExpressions.Regex.IsMatch(sha, "^[0-9a-f]{40}$") ? sha : null;
        }
        catch (Exception) { return null; }
    }

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
    public static Task<string?> Prepare(bool dlss, bool fsr, Action<string> line, CancellationToken token)
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
            if (fsr) si.ArgumentList.Add("-AcceptAmdLicense");   // (AMD's files only with AMD's license accepted on the FSR 4 tick)
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
}
