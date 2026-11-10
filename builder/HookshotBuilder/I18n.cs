using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace HookshotBuilder;

/// (fork) The builder's window in the language chosen (the Game language box), as the game's Insert menu does it
/// (gpu/vk/vk_menu_i18n.cpp): its English texts looked up in a table, exactly, or as a template whose {0}, {1}... stand for
/// what the code put in (each translated in turn when it is a text of the table too). The table (i18n.json, inside the app)
/// is made from the builder's own texts. The window's texts are translated where they are shown: each text block, button
/// and tooltip of the window, when its English text changes (a quick look a few times a second) or the language does;
/// message boxes and file dialogs through Tr. What is not in the table stays English; the details log is never translated.
static class I18n
{
    static readonly Dictionary<string, Dictionary<string, string>> Tables = Load();
    static Dictionary<string, string>? table;
    static List<(Regex Re, string Key)> templates = new();
    static List<(Regex Re, string Key)> fragments = new();
    static List<string> plainFragments = new();

    static Dictionary<string, Dictionary<string, string>> Load()
    {
        try
        {
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("HookshotBuilder.i18n.json");
            if (s == null) return new();
            return JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(s) ?? new();
        }
        catch (Exception) { return new(); }
    }

    /// The table for a language code of Strings.All (fr-CA takes French's, es-419 Spanish's, pt-BR "pt"); English: none
    static string? Family(string code) => code switch
    {
        "pt-BR" => "pt",
        "fr-CA" => "fr",
        "es-419" => "es",
        _ => code.StartsWith("en") ? null : code,
    };

    public static string Code { get; private set; } = "en-US";

    public static void Use(string code)
    {
        Code = code;
        table = Family(code) is { } f && Tables.TryGetValue(f, out var t) ? t : null;
        templates = new();
        fragments = new();
        plainFragments = new();
        if (table == null) return;
        foreach (var key in table.Keys.OrderByDescending(k => k.Length))
        {
            var fragment = key.StartsWith(' ') || key.StartsWith(". ") || key.StartsWith('\n');
            var holes = Regex.IsMatch(key, @"(?<!\{)\{\d+\}");
            if (!holes)
            {
                if (fragment) plainFragments.Add(key);
                continue;
            }
            var pattern = Regex.Replace(Regex.Escape(key.Replace("{{", "{").Replace("}}", "}")), @"\\\{(\d+)}", m => $"(?<h{m.Groups[1].Value}>.+?)");
            if (fragment) fragments.Add((new Regex(pattern, RegexOptions.Singleline | RegexOptions.CultureInvariant), key));
            else templates.Add((new Regex("^" + pattern + "$", RegexOptions.Singleline | RegexOptions.CultureInvariant), key));
        }
    }

    /// What a template's holes took is one value each, not a line of the window: never across a " · " or a line break
    static bool Holes(Match m)
    {
        for (var i = 1; i < m.Groups.Count; i++)
            if (m.Groups[i].Value.Contains(" · ") || m.Groups[i].Value.Contains('\n')) return false;
        return true;
    }

    static string Fill(string translated, Match m) => Regex.Replace(translated.Replace("{{", "\x01").Replace("}}", "\x02"), @"\{(\d+)\}", h =>
    {
        var g = m.Groups["h" + h.Groups[1].Value];
        if (!g.Success) return h.Value;
        return table!.TryGetValue(g.Value, out var inner) ? inner : g.Value;
    }).Replace("\x01", "{").Replace("\x02", "}");

    /// A text in the chosen language: the table's, else the text as it is
    public static string Tr(string text)
    {
        if (table == null || string.IsNullOrEmpty(text)) return text;
        if (table.TryGetValue(text, out var exact)) return exact;
        // (a file's name or a bare path: only the fragments appended to it, never a template over the whole)
        var named = text.EndsWith(".nup", StringComparison.OrdinalIgnoreCase) || Regex.IsMatch(text, @"^(?:[A-Za-z]:\\|\\\\)\S*$");
        if (!named)
            foreach (var (re, key) in templates)
                if (re.Match(text) is { Success: true } m && Holes(m)) return Fill(table[key], m);
        // (a line the code put together from parts, "Usually about 45 minutes · your PC stays usable": each part on its own)
        if (!named && text.Contains(" · "))
        {
            var parts = text.Split(" · ");
            var changed = false;
            for (var i = 0; i < parts.Length; i++)
            {
                var p = Part(parts[i], i > 0);
                changed |= p != parts[i];
                parts[i] = p;
            }
            if (changed) return string.Join(" · ", parts);
        }
        var result = text;
        foreach (var key in plainFragments)
            if (result.Contains(key)) result = result.Replace(key, table[key]);
        foreach (var (re, key) in fragments)
            result = re.Replace(result, m => Fill(table[key], m));
        return result;
    }

    /// One part of a line put together with " · ": the table's text for it, or for it as a part after a " · ", or a template
    static string Part(string p, bool after)
    {
        if (table!.TryGetValue(p, out var t)) return t;
        if (after && table.TryGetValue(" · " + p, out var f) && f.StartsWith(" · ")) return f[3..];
        foreach (var (re, key) in templates)
            if (re.Match(p) is { Success: true } m && Holes(m)) return Fill(table[key], m);
        return p;
    }

    // ---- the window's texts, where they are shown ----

    // (each text block and control is watched from when it is first seen: a text the code sets is translated at once, before
    // the window draws it, so it never shows in English first)
    static readonly ConditionalWeakTable<object, object> watched = new();
    static readonly System.ComponentModel.DependencyPropertyDescriptor TextProp =
        System.ComponentModel.DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty, typeof(TextBlock));
    static readonly System.ComponentModel.DependencyPropertyDescriptor ContentProp =
        System.ComponentModel.DependencyPropertyDescriptor.FromProperty(ContentControl.ContentProperty, typeof(ContentControl));

    static void Watch(TextBlock tb)
    {
        if (watched.TryGetValue(tb, out _)) return;
        watched.Add(tb, true);
        TextProp.AddValueChanged(tb, (_, _) =>
        {
            if (tb.Text.Length == 0 || tb.Inlines.Count > 1) return;
            var t = Show(tb, tb.Text, false);
            if (t != tb.Text) tb.Text = t;
        });
    }

    static void Watch(ContentControl cc)
    {
        if (watched.TryGetValue(cc, out _)) return;
        watched.Add(cc, true);
        ContentProp.AddValueChanged(cc, (_, _) =>
        {
            if (cc.Content is not string text || text.Length == 0) return;
            var t = Show(cc, text, false);
            if (t != text) cc.Content = t;
        });
    }

    sealed class Seen { public string English = "", Shown = ""; }
    static readonly ConditionalWeakTable<object, Seen> seen = new(), tips = new();

    static string Show(object owner, string now, bool again, bool tip = false)
    {
        var s = (tip ? tips : seen).GetOrCreateValue(owner);
        if (now != s.Shown || s.English.Length == 0) s.English = now;   // (the code set a new English text)
        else if (!again) return now;
        s.Shown = Tr(s.English);
        return s.Shown;
    }

    /// Every text of the window in the chosen language. again: the language changed (each from its English again)
    public static void Apply(DependencyObject root, bool again = false)
    {
        var stack = new Stack<DependencyObject>();
        stack.Push(root);
        while (stack.Count > 0)
        {
            var d = stack.Pop();
            if (d is TextBox) continue;   // (the player's paths, and the details log: never translated)
            if (d is FrameworkElement fe)
            {
                if (fe.ToolTip is string tip && tip.Length > 0)
                {
                    var t = Show(fe, tip, again, tip: true);
                    if (t != tip) fe.ToolTip = t;
                }
                // (a text a control's template shows, its Content: translated on the control, not here)
                if (fe is TextBlock tb && tb.TemplatedParent == null)
                {
                    if (tb.Inlines.Count > 1 || tb.Inlines.FirstOrDefault() is not Run)
                    {
                        foreach (var run in tb.Inlines.OfType<Run>())
                        {
                            var t = Show(run, run.Text, again);
                            if (t != run.Text) run.Text = t;
                        }
                    }
                    else if (tb.Text.Length > 0 || !watched.TryGetValue(tb, out _))
                    {
                        Watch(tb);
                        var t = Show(tb, tb.Text, again);
                        if (t != tb.Text) tb.Text = t;
                    }
                }
                else if (fe is ContentControl cc && fe is not Window && (cc.Content is string { Length: > 0 } || cc.Content == null))
                {
                    Watch(cc);
                    if (cc.Content is string text)
                    {
                        var t = Show(cc, text, again);
                        if (t != text) cc.Content = t;
                    }
                }
            }
            if (d is Visual or System.Windows.Media.Media3D.Visual3D)
                for (int i = VisualTreeHelper.GetChildrenCount(d) - 1; i >= 0; i--) stack.Push(VisualTreeHelper.GetChild(d, i));
            // (pages not shown yet are not in the visual tree: their logical children too)
            foreach (var child in LogicalTreeHelper.GetChildren(d).OfType<DependencyObject>())
                if (child is not Visual v || VisualTreeHelper.GetParent(v) == null) stack.Push(child);
        }
    }
}

/// (fork) MessageBox.Show with its text and caption in the chosen language (I18n.Tr): every message box of the builder
static class MessageBox
{
    public static MessageBoxResult Show(Window owner, string text, string caption) =>
        System.Windows.MessageBox.Show(owner, I18n.Tr(text), I18n.Tr(caption));
    public static MessageBoxResult Show(Window owner, string text, string caption, MessageBoxButton button) =>
        System.Windows.MessageBox.Show(owner, I18n.Tr(text), I18n.Tr(caption), button);
    public static MessageBoxResult Show(Window owner, string text, string caption, MessageBoxButton button, MessageBoxImage icon) =>
        System.Windows.MessageBox.Show(owner, I18n.Tr(text), I18n.Tr(caption), button, icon);
    public static MessageBoxResult Show(string text, string caption) => System.Windows.MessageBox.Show(I18n.Tr(text), I18n.Tr(caption));
    public static MessageBoxResult Show(string text) => System.Windows.MessageBox.Show(I18n.Tr(text));
}
