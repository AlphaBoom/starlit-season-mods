// Copyright (c) 2026 AlphaBoom. MIT licensed.
// Mod manager for THE IDOLM@STER STARLIT SEASON (Steam v1.61).
// Lives in the game root next to StarlitSeason.exe; its data is in StarlitModsData.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace StarlitMods {
 public sealed class PackageFile { public string Path; public string Sha256; }
 public sealed class Manifest {
  public string Version; public string GameExeSha256; public string SmokeSha256;
  public PackageFile[] Files;
 }
 // UI language: Chinese on Chinese Windows, English elsewhere; switchable in the window.
 public static class L {
  public static bool Zh = System.Globalization.CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
  public static string T(string zh, string en) { return Zh ? zh : en; }
 }
 public sealed class Status { public bool Auto, Dialogue, Dlc, Loader, GameMatches; }

 public sealed class Manager {
  public const string AutoMod = "TextAutoToggle", DialogueMod = "DialogueMenu";
  public readonly string Root, Data, Payload, Bin, SteamDir;
  public readonly Manifest Manifest;
  readonly JavaScriptSerializer json = new JavaScriptSerializer();

  public Manager(string root) {
   Root = Path.GetFullPath(root).TrimEnd('\\', '/');
   Bin = Under(Root, "StarlitSeason/Binaries/Win64");
   if (!File.Exists(Under(Bin, "StarlitSeason-Win64-Shipping.exe")))
    throw new IOException(L.T("请把压缩包解压到游戏根目录（含 StarlitSeason.exe 的文件夹），再打开 StarlitMods.exe。\n\n在 Steam 中右键游戏 → 管理 → 浏览本地文件 即可打开该目录。", "Extract the package into the game folder (the one with StarlitSeason.exe), then open StarlitMods.exe.\n\nIn Steam: right-click the game > Manage > Browse local files."));
   Data = Under(Root, "StarlitModsData"); Payload = Under(Data, "payload");
   SteamDir = Under(Root, "Engine/Binaries/ThirdParty/Steamworks/Steamv146/Win64");
   Manifest = json.Deserialize<Manifest>(File.ReadAllText(Under(Data, "manifest.json")));
  }
  public static string Under(string root, string relative) {
   string prefix = Path.GetFullPath(root).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
   string full = Path.GetFullPath(Path.Combine(prefix, relative.Replace('/', Path.DirectorySeparatorChar)));
   if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new IOException("Unsafe package path: " + relative);
   return full;
  }
  public static string Hash(string path) {
   using (var sha = SHA256.Create()) using (var stream = File.OpenRead(path))
    return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
  }
  static bool HashIs(string path, string sha) {
   return File.Exists(path) && Hash(path).Equals(sha, StringComparison.OrdinalIgnoreCase);
  }
  public bool FirstRun { get { return !File.Exists(Under(Data, "state.json")); } }
  string ModsTxt { get { return Under(Bin, "ue4ss/Mods/mods.txt"); } }
  string Api { get { return Under(SteamDir, "steam_api64.dll"); } }
  string ApiOriginal { get { return Under(SteamDir, "steam_api64_o.dll"); } }

  public Status Read() {
   var s = new Status();
   string mods = File.Exists(ModsTxt) ? File.ReadAllText(ModsTxt) : "";
   s.Auto = Enabled(mods, AutoMod); s.Dialogue = Enabled(mods, DialogueMod);
   s.Dlc = HashIs(Api, Manifest.SmokeSha256);
   s.Loader = File.Exists(Under(Bin, "dwmapi.dll")) && File.Exists(Under(Bin, "ue4ss/UE4SS.dll"));
   s.GameMatches = HashIs(Under(Bin, "StarlitSeason-Win64-Shipping.exe"), Manifest.GameExeSha256);
   return s;
  }
  static bool Enabled(string mods, string name) {
   return Regex.IsMatch(mods, @"(?m)^\s*" + name + @"\s*:\s*1\s*$");
  }
  public static string SetMods(string text, bool auto, bool dialogue) {
   text = Regex.Replace(text, @"(?m)^\s*(" + AutoMod + "|" + DialogueMod + @")\s*:.*(?:\r?\n|$)", "");
   return text.TrimEnd() + (text.Trim().Length > 0 ? "\r\n" : "") +
    AutoMod + " : " + (auto ? "1" : "0") + "\r\n" + DialogueMod + " : " + (dialogue ? "1" : "0") + "\r\n";
  }
  void EnsureClosed() {
   if (Process.GetProcessesByName("StarlitSeason-Win64-Shipping").Length != 0)
    throw new IOException(L.T("请先关闭游戏，再修改 Mod。", "Close the game before changing mods."));
  }
  void EnsureGame() {
   if (!HashIs(Under(Bin, "StarlitSeason-Win64-Shipping.exe"), Manifest.GameExeSha256))
    throw new IOException(L.T("游戏版本与本 Mod 包不匹配（仅支持 Steam v1.61）。未修改任何文件。", "This game version is not supported (Steam v1.61 only). No files were changed."));
  }
  // Restores any missing or altered package file from the verified payload copy.
  void Deploy() {
   foreach (var f in Manifest.Files) {
    string source = Under(Payload, f.Path);
    if (!HashIs(source, f.Sha256)) throw new IOException(L.T("Mod 包文件损坏或不完整：", "Mod package file missing or damaged: ") + f.Path + L.T("\n请重新解压完整的 Release 压缩包。", "\nExtract the full release zip again."));
    string dest = Under(Root, f.Path);
    if (f.Path.EndsWith("/mods.txt", StringComparison.OrdinalIgnoreCase) && File.Exists(dest)) continue;
    if (HashIs(dest, f.Sha256)) continue;
    Directory.CreateDirectory(Path.GetDirectoryName(dest));
    File.Copy(source, dest, true);
   }
  }
  void Dlc(bool enable) {
   bool smoke = HashIs(Api, Manifest.SmokeSha256);
   string config = Under(SteamDir, "SmokeAPI.config.json");
   if (enable) {
    if (!File.Exists(Api)) throw new IOException(L.T("找不到游戏的 steam_api64.dll。", "The game's steam_api64.dll was not found."));
    if (smoke) {
     if (!File.Exists(ApiOriginal)) throw new IOException(L.T("缺少原始 steam_api64_o.dll，无法安全管理 DLC 解锁。请在 Steam 中验证游戏文件完整性后重试。", "The original steam_api64_o.dll is missing, so DLC unlock cannot be managed safely. Verify the game files in Steam and try again."));
    } else {
     // The current file is the game's own Steam API (possibly updated by Steam).
     File.Copy(Api, ApiOriginal, true);
     File.Copy(Under(Payload, "dlc/smoke_api64.dll"), Api, true);
    }
    File.Copy(Under(Payload, "dlc/SmokeAPI.config.json"), config, true);
   } else if (smoke) {
    if (!File.Exists(ApiOriginal)) throw new IOException(L.T("缺少原始 steam_api64_o.dll，无法恢复。请在 Steam 中验证游戏文件完整性。", "The original steam_api64_o.dll is missing and cannot be restored. Verify the game files in Steam."));
    File.Copy(ApiOriginal, Api, true);
    File.Delete(ApiOriginal);
    foreach (string name in new[] { "SmokeAPI.config.json", "SmokeAPI.cache.json", "SmokeAPI.log.log" }) {
     string p = Under(SteamDir, name); if (File.Exists(p)) File.Delete(p);
    }
   }
  }
  void WriteState(string text) {
   Directory.CreateDirectory(Data);
   File.WriteAllText(Under(Data, "state.json"), text, new UTF8Encoding(false));
  }
  // VoiceWatchdog shipped in 1.1.0 and was withdrawn: remove its files when they are the
  // 1.1.0 ones (a different, locally tested build is left alone) and then its mods.txt line.
  static readonly string[][] Retired = {
   new[] { "ue4ss/Mods/VoiceWatchdog/Scripts/main.lua", "34F5F08192D964D4A0BE3EE5BF20FF6161F93A9681547B0D232F12988E71327B" },
   new[] { "ue4ss/Mods/VoiceWatchdog/durations.tsv", "8483A2CD92ADEE1824D64A87AD87287D7752371575A54D4EFB5A9C542E6E6044" },
   new[] { "ue4ss/Mods/VoiceWatchdog/README.md", "E1D415EB3F5B14D686C6E47089E308C75F0F09F107BBC2CC829B28DBAACD00C2" },
  };
  void RemoveRetired() {
   string script = Under(Bin, Retired[0][0]);
   if (File.Exists(script) && !HashIs(script, Retired[0][1])) return;
   foreach (var r in Retired) { string p = Under(Bin, r[0]); if (HashIs(p, r[1])) File.Delete(p); }
   string dir = Under(Bin, "ue4ss/Mods/VoiceWatchdog");
   string log = Path.Combine(dir, "watchdog.log");
   if (File.Exists(log)) File.Delete(log);
   foreach (string d in new[] { Path.Combine(dir, "Scripts"), dir })
    if (Directory.Exists(d) && !Directory.EnumerateFileSystemEntries(d).Any()) Directory.Delete(d);
   if (File.Exists(ModsTxt)) {
    string text = File.ReadAllText(ModsTxt);
    string rest = Regex.Replace(text, @"(?m)^\s*VoiceWatchdog\s*:.*(?:\r?\n|$)", "");
    if (rest != text) File.WriteAllText(ModsTxt, rest, new UTF8Encoding(false));
   }
  }
  public void Apply(bool auto, bool dialogue, bool dlc) {
   EnsureClosed(); EnsureGame();
   RemoveRetired();
   Deploy();
   File.WriteAllText(ModsTxt, SetMods(File.Exists(ModsTxt) ? File.ReadAllText(ModsTxt) : "", auto, dialogue), new UTF8Encoding(false));
   Dlc(dlc);
   WriteState(json.Serialize(new { Version = Manifest.Version, Auto = auto, Dialogue = dialogue, Dlc = dlc }));
  }
  public void Uninstall() {
   EnsureClosed();
   RemoveRetired();
   Dlc(false);
   foreach (var f in Manifest.Files) {
    string dest = Under(Root, f.Path);
    if (f.Path.EndsWith("/mods.txt", StringComparison.OrdinalIgnoreCase)) {
     if (!File.Exists(dest)) continue;
     string rest = Regex.Replace(File.ReadAllText(dest), @"(?m)^\s*(" + AutoMod + "|" + DialogueMod + @")\s*:.*(?:\r?\n|$)", "");
     if (rest.Trim().Length == 0) File.Delete(dest); else File.WriteAllText(dest, rest, new UTF8Encoding(false));
    } else if (HashIs(dest, f.Sha256)) File.Delete(dest);
   }
   // Remove folders left empty; anything another mod added stays.
   foreach (var f in Manifest.Files) {
    string dir = Path.GetDirectoryName(Under(Root, f.Path));
    while (dir.Length > Bin.Length && dir.StartsWith(Bin, StringComparison.OrdinalIgnoreCase) &&
           Directory.Exists(dir) && !Directory.EnumerateFileSystemEntries(dir).Any()) {
     Directory.Delete(dir); dir = Path.GetDirectoryName(dir);
    }
   }
   WriteState(json.Serialize(new { Version = Manifest.Version, Uninstalled = true }));
  }
 }

 // Window styled after the game's menus: pastel sky background with bubbles,
 // a teal MENU banner, white cards, gold / silver pointed buttons and the
 // slate help bar along the bottom. Everything is painted here; no child controls.
 public sealed class ManagerForm : Form {
  sealed class Option { public string Title, Detail; public bool On; public RectangleF Card, Toggle; }
  sealed class Command { public string Text; public bool Primary; public Action Click; public RectangleF Box; }
  static readonly Color Ink = Color.FromArgb(58, 74, 92), Muted = Color.FromArgb(118, 132, 146);
  static readonly Color Teal = Color.FromArgb(52, 189, 183), TealDark = Color.FromArgb(32, 150, 150);
  static readonly Color Slate = Color.FromArgb(62, 79, 99), Gold = Color.FromArgb(122, 90, 18);
  readonly Manager manager;
  readonly Option[] options;
  readonly Command[] commands;
  readonly float k; // DPI scale
  string status = "";
  object hover;
  public ManagerForm(Manager m) {
   manager = m;
   using (var g = CreateGraphics()) k = g.DpiX / 96f;
   AutoScaleMode = AutoScaleMode.None;
   ClientSize = new Size(S(760), S(560));
   FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false;
   StartPosition = FormStartPosition.CenterScreen;
   DoubleBuffered = true;
   Font = new Font("Microsoft YaHei UI", 10);
   string saved = Path.Combine(manager.Data, "language.txt");
   if (File.Exists(saved)) L.Zh = File.ReadAllText(saved).Trim() == "zh";
   options = new[] { new Option(), new Option(), new Option() };
   commands = new[] {
    new Command { Primary = true, Click = () => Run(() => manager.Apply(options[0].On, options[1].On, options[2].On), L.T("已应用，下次启动游戏生效。", "Applied. Takes effect the next time the game starts.")) },
    new Command { Click = () => {
     if (MessageBox.Show(this, L.T("卸载本包安装的全部 Mod 和加载器，并恢复原有 Steam API？\n\n存档（包括 QUICK 存档位）会保留。", "Remove every mod and the loader installed by this package, and restore the original Steam API?\n\nSaves (including the QUICK slot) are kept."), L.T("卸载 Mod", "Uninstall mods"), MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
      Run(manager.Uninstall, L.T("已卸载。可删除 StarlitMods.exe 和 StarlitModsData 文件夹；重新点“应用”可再次安装。", "Uninstalled. You can delete StarlitMods.exe and the StarlitModsData folder, or press Apply to reinstall."));
    } },
    new Command { Click = () => Process.Start("explorer.exe", manager.Root) },
    new Command { Click = () => {
     L.Zh = !L.Zh;
     try { File.WriteAllText(saved, L.Zh ? "zh" : "en"); } catch (IOException) { }
     Texts(); status = Hint(); Invalidate();
    } },
   };
   Texts();
   for (int i = 0; i < options.Length; i++) {
    options[i].Card = R(40, 128 + i * 98, 680, 84);
    options[i].Toggle = R(40 + 680 - 24 - 64, 128 + i * 98 + 26, 64, 32);
   }
   for (int i = 0; i < 3; i++) commands[i].Box = R(52 + i * 226, 432, 204, 50);
   commands[3].Box = R(640, 50, 96, 26);
   Shown += (s, e) => {
    // First run: the two dialogue mods on; DLC unlock stays off until the user enables it.
    if (manager.FirstRun) Run(() => manager.Apply(true, true, false), L.T("首次运行：已启用对话自动切换和存读档增强。DLC 解锁需要手动开启。", "First run: dialogue auto toggle and save / load enabled. DLC unlock is off until you turn it on."));
    else Run(() => { }, Hint());
   };
  }
  static string Hint() { return L.T("点击卡片切换功能，然后点“应用”。修改前请先关闭游戏。", "Click a card to switch a mod, then press Apply. Close the game first."); }
  void Texts() {
   Text = L.T("STARLIT SEASON Mod 管理器 ", "STARLIT SEASON Mod Manager ") + manager.Manifest.Version;
   options[0].Title = L.T("对话自动 / 手动切换", "Dialogue auto / manual toggle");
   options[0].Detail = L.T("对话中按 手柄 Y / 三角键 或 键盘 A 切换，提示栏显示 AUTO ON / OFF", "Gamepad Y / Triangle or keyboard A in dialogue; the guide bar shows AUTO ON / OFF");
   options[1].Title = L.T("对话存读档增强", "Save / load in dialogue");
   options[1].Detail = L.T("菜单增加 SAVE / LOAD · 独立 QUICK 存档位 · F5 快存 / F6 快读", "SAVE / LOAD in the dialogue menu · separate QUICK slot · F5 quick save / F6 quick load");
   options[2].Title = L.T("DLC 解锁", "DLC unlock");
   options[2].Detail = L.T("SmokeAPI 4.1.3 · 默认关闭 · 关闭时恢复游戏原有的 Steam API", "SmokeAPI 4.1.3 · off by default · turning it off restores the game's Steam API");
   commands[0].Text = L.T("应用", "Apply");
   commands[1].Text = L.T("卸载全部 Mod", "Uninstall all");
   commands[2].Text = L.T("打开游戏目录", "Game folder");
   commands[3].Text = L.T("English", "中文");
  }
  int S(float v) { return (int)Math.Round(v * k); }
  RectangleF R(float x, float y, float w, float h) { return new RectangleF(x * k, y * k, w * k, h * k); }
  static Font F(float size, FontStyle style) { return new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Point); }

  void Run(Action work, string message) {
   try { work(); status = message; }
   catch (Exception ex) { status = L.T("操作未完成：", "Not completed: ") + ex.Message.Split('\n')[0]; MessageBox.Show(this, ex.Message, L.T("Mod 管理器", "Mod Manager"), MessageBoxButtons.OK, MessageBoxIcon.Warning); }
   var st = manager.Read();
   options[0].On = st.Auto; options[1].On = st.Dialogue; options[2].On = st.Dlc;
   if (!st.GameMatches) status += L.T("  注意：游戏版本不是本包支持的 Steam v1.61。", "  Note: this game version is not Steam v1.61.");
   else if (!st.Loader) status += L.T("  加载器未安装：点“应用”安装。", "  Loader not installed: press Apply.");
   Invalidate();
  }
  object HitTest(Point p) {
   foreach (var o in options) if (o.Card.Contains(p)) return o;
   foreach (var c in commands) if (c.Box.Contains(p)) return c;
   return null;
  }
  protected override void OnMouseMove(MouseEventArgs e) {
   var h = HitTest(e.Location);
   if (h != hover) { hover = h; Cursor = h != null ? Cursors.Hand : Cursors.Default; Invalidate(); }
  }
  protected override void OnMouseLeave(EventArgs e) { hover = null; Invalidate(); }
  protected override void OnMouseClick(MouseEventArgs e) {
   if (e.Button != MouseButtons.Left) return;
   var h = HitTest(e.Location);
   var o = h as Option; if (o != null) { o.On = !o.On; status = L.T("已更改，点“应用”后生效。", "Changed. Press Apply to use it."); Invalidate(); }
   var c = h as Command; if (c != null) c.Click();
  }

  static GraphicsPath Round(RectangleF r, float radius) {
   var p = new GraphicsPath(); float d = radius * 2;
   p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
   p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
   p.CloseFigure(); return p;
  }
  // The game's buttons and labels: a bar with pointed ends.
  static GraphicsPath Hexagon(RectangleF r) {
   float t = r.Height / 2;
   var p = new GraphicsPath();
   p.AddPolygon(new[] { new PointF(r.X, r.Y + t), new PointF(r.X + t, r.Y), new PointF(r.Right - t, r.Y),
    new PointF(r.Right, r.Y + t), new PointF(r.Right - t, r.Bottom), new PointF(r.X + t, r.Bottom) });
   return p;
  }
  static PointF[] Diamond(float x, float y, float d) {
   return new[] { new PointF(x, y - d), new PointF(x + d, y), new PointF(x, y + d), new PointF(x - d, y) };
  }
  void Sparkle(Graphics g, float x, float y, float size, int alpha) {
   x *= k; y *= k; size *= k; float w = size / 5;
   using (var b = new SolidBrush(Color.FromArgb(alpha, Color.White)))
    g.FillPolygon(b, new[] { new PointF(x, y - size), new PointF(x + w, y - w), new PointF(x + size, y), new PointF(x + w, y + w),
     new PointF(x, y + size), new PointF(x - w, y + w), new PointF(x - size, y), new PointF(x - w, y - w) });
  }
  void Bubble(Graphics g, float x, float y, float r, int alpha) {
   var rect = R(x - r, y - r, r * 2, r * 2);
   using (var path = new GraphicsPath()) {
    path.AddEllipse(rect);
    using (var b = new PathGradientBrush(path)) {
     b.CenterColor = Color.FromArgb(alpha / 4, Color.White);
     b.SurroundColors = new[] { Color.FromArgb(alpha, Color.White) };
     g.FillPath(b, path);
    }
   }
   using (var pen = new Pen(Color.FromArgb(Math.Min(255, alpha + 40), Color.White), 1.2f * k)) g.DrawEllipse(pen, rect);
  }
  static void Center(Graphics g, string text, Font f, Color c, RectangleF r) {
   var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
   using (var b = new SolidBrush(c)) g.DrawString(text, f, b, r, fmt);
  }

  protected override void OnPaint(PaintEventArgs e) {
   var g = e.Graphics;
   g.SmoothingMode = SmoothingMode.AntiAlias;
   g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
   var all = new RectangleF(0, 0, ClientSize.Width, ClientSize.Height);
   // Sky to cream, like the title screen.
   using (var b = new LinearGradientBrush(all, Color.White, Color.White, 90f)) {
    var blend = new ColorBlend();
    blend.Colors = new[] { Color.FromArgb(150, 214, 240), Color.FromArgb(214, 238, 247), Color.FromArgb(248, 244, 226), Color.FromArgb(252, 232, 178) };
    blend.Positions = new[] { 0f, 0.45f, 0.78f, 1f };
    b.InterpolationColors = blend; g.FillRectangle(b, all);
   }
   Bubble(g, 70, 70, 46, 70); Bubble(g, 150, 26, 22, 60); Bubble(g, 690, 60, 54, 60); Bubble(g, 610, 18, 18, 55);
   Bubble(g, 738, 384, 30, 45); Bubble(g, 22, 412, 26, 45); Bubble(g, 404, 112, 12, 50);
   Sparkle(g, 560, 30, 14, 230); Sparkle(g, 232, 96, 9, 200); Sparkle(g, 726, 116, 11, 220); Sparkle(g, 26, 160, 8, 180);
   Sparkle(g, 712, 414, 9, 200);

   // MENU banner: translucent bar with a teal pointed label.
   using (var b = new SolidBrush(Color.FromArgb(110, 120, 136, 150))) g.FillRectangle(b, R(0, 48, 760, 30));
   var label = R(200, 40, 360, 46);
   using (var path = Hexagon(label)) {
    using (var b = new LinearGradientBrush(label, Color.FromArgb(96, 216, 208), TealDark, 90f)) g.FillPath(b, path);
    using (var pen = new Pen(Color.FromArgb(220, Color.White), 1.6f * k)) g.DrawPath(pen, path);
   }
   using (var f = new Font("Segoe UI", 15, FontStyle.Bold)) Center(g, "MOD MENU", f, Color.White, label);
   using (var f = F(9, FontStyle.Regular))
    Center(g, "THE IDOLM@STER STARLIT SEASON  ·  Steam v1.61  ·  " + manager.Manifest.Version, f, Slate, R(0, 92, 760, 22));

   foreach (var o in options) DrawOption(g, o);
   for (int i = 0; i < 3; i++) DrawCommand(g, commands[i]);
   DrawLanguage(g, commands[3]);

   // Help bar, like the game's bottom guide.
   using (var b = new SolidBrush(Color.FromArgb(230, Slate))) g.FillRectangle(b, R(0, 506, 760, 54));
   using (var b = new SolidBrush(Teal)) g.FillRectangle(b, R(0, 506, 760, 3));
   using (var f = F(9.5f, FontStyle.Regular)) {
    var fmt = new StringFormat { LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter };
    using (var b = new SolidBrush(Color.White)) g.DrawString(status, f, b, R(28, 509, 704, 51), fmt);
   }
  }
  void DrawOption(Graphics g, Option o) {
   bool hot = hover == o;
   var card = o.Card;
   using (var shadow = Round(new RectangleF(card.X, card.Y + 3 * k, card.Width, card.Height), 10 * k))
   using (var b = new SolidBrush(Color.FromArgb(30, 40, 70, 100))) g.FillPath(b, shadow);
   using (var path = Round(card, 10 * k)) {
    using (var b = new SolidBrush(Color.FromArgb(hot ? 252 : 238, Color.White))) g.FillPath(b, path);
    using (var pen = new Pen(hot ? Color.FromArgb(232, 198, 100) : Color.FromArgb(170, Color.White), (hot ? 2f : 1.2f) * k)) g.DrawPath(pen, path);
   }
   var accent = o.On ? Teal : Color.FromArgb(192, 202, 212);
   using (var b = new SolidBrush(accent)) {
    g.FillRectangle(b, card.X, card.Y + 14 * k, 5 * k, card.Height - 28 * k);
    g.FillPolygon(b, Diamond(card.X + 30 * k, card.Y + 30 * k, 7 * k));
   }
   using (var f = F(12.5f, FontStyle.Bold)) using (var b = new SolidBrush(Ink)) g.DrawString(o.Title, f, b, card.X + 46 * k, card.Y + 15 * k);
   using (var f = F(9.5f, FontStyle.Regular)) using (var b = new SolidBrush(Muted)) g.DrawString(o.Detail, f, b, card.X + 46 * k, card.Y + 48 * k);
   // Toggle switch.
   var t = o.Toggle;
   using (var path = Round(t, t.Height / 2)) {
    if (o.On) using (var b = new LinearGradientBrush(t, Color.FromArgb(100, 220, 212), TealDark, 90f)) g.FillPath(b, path);
    else using (var b = new SolidBrush(Color.FromArgb(208, 216, 224))) g.FillPath(b, path);
   }
   float knob = t.Height - 6 * k;
   var kr = new RectangleF(o.On ? t.Right - knob - 3 * k : t.X + 3 * k, t.Y + 3 * k, knob, knob);
   using (var b = new SolidBrush(Color.FromArgb(40, 0, 0, 0))) g.FillEllipse(b, kr.X, kr.Y + 1.5f * k, kr.Width, kr.Height);
   using (var b = new SolidBrush(Color.White)) g.FillEllipse(b, kr);
   var textArea = o.On ? new RectangleF(t.X, t.Y, t.Width - knob - 3 * k, t.Height) : new RectangleF(t.X + knob + 3 * k, t.Y, t.Width - knob - 3 * k, t.Height);
   using (var f = new Font("Segoe UI", 8, FontStyle.Bold)) Center(g, o.On ? "ON" : "OFF", f, o.On ? Color.White : Muted, textArea);
  }
  // Small language switch in the banner, top right.
  void DrawLanguage(Graphics g, Command c) {
   var r = c.Box;
   using (var path = Round(r, r.Height / 2)) {
    using (var b = new SolidBrush(Color.FromArgb(hover == c ? 250 : 215, Color.White))) g.FillPath(b, path);
    using (var pen = new Pen(hover == c ? Color.FromArgb(232, 198, 100) : Color.FromArgb(160, Teal), 1.2f * k)) g.DrawPath(pen, path);
   }
   using (var f = F(9, FontStyle.Bold)) Center(g, c.Text, f, TealDark, r);
  }
  void DrawCommand(Graphics g, Command c) {
   bool hot = hover == c, gold = c.Primary || hot;
   var r = c.Box;
   using (var shadow = Hexagon(new RectangleF(r.X, r.Y + 3 * k, r.Width, r.Height)))
   using (var b = new SolidBrush(Color.FromArgb(35, 40, 60, 90))) g.FillPath(b, shadow);
   using (var path = Hexagon(r)) {
    var top = gold ? Color.FromArgb(255, 247, 206) : Color.White;
    var bottom = gold ? Color.FromArgb(236, 202, 98) : Color.FromArgb(205, 211, 218);
    using (var b = new LinearGradientBrush(r, top, bottom, 90f)) g.FillPath(b, path);
    // Diamond pattern on the left end, as on the game's selected buttons.
    var clip = g.Clip; g.SetClip(path, CombineMode.Intersect);
    using (var b = new SolidBrush(Color.FromArgb(gold ? 80 : 60, Color.White)))
     for (int i = 0; i < 5; i++) g.FillPolygon(b, Diamond(r.X + (14 + i * 14) * k, r.Y + r.Height / 2 + (i % 2 == 0 ? -8 : 8) * k, 10 * k));
    g.Clip = clip;
    using (var pen = new Pen(gold ? Color.FromArgb(226, 190, 90) : Color.FromArgb(180, 188, 198), 1.4f * k)) g.DrawPath(pen, path);
   }
   using (var f = F(11, FontStyle.Bold)) Center(g, c.Text, f, gold ? Gold : Color.FromArgb(90, 100, 112), r);
  }
 }

 public static class Program {
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  [STAThread]
  public static int Main(string[] args) {
   SetProcessDPIAware();
   Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
   bool cli = args.Length > 0;
   try {
    string root = AppDomain.CurrentDomain.BaseDirectory;
    if (args.Length > 1 && args[0] == "--root") { root = args[1]; args = args.Skip(2).ToArray(); cli = args.Length > 0; }
    var manager = new Manager(root);
    if (!cli) { Application.Run(new ManagerForm(manager)); return 0; }
    if (args[0] == "--apply" && args.Length == 4) manager.Apply(args[1] == "1", args[2] == "1", args[3] == "1");
    else if (args[0] == "--uninstall") manager.Uninstall();
    else if (args[0] != "--status") throw new ArgumentException("Usage: StarlitMods.exe [--root DIR] [--status | --apply AUTO DIALOGUE DLC | --uninstall]");
    var st = manager.Read();
    Console.WriteLine("Auto={0} Dialogue={1} Dlc={2} Loader={3} GameMatches={4}", st.Auto, st.Dialogue, st.Dlc, st.Loader, st.GameMatches);
    return 0;
   } catch (Exception ex) {
    if (cli) Console.Error.WriteLine(ex.Message); else MessageBox.Show(ex.Message, L.T("Mod 管理器", "Mod Manager"), MessageBoxButtons.OK, MessageBoxIcon.Error);
    return 1;
   }
  }
 }
}
