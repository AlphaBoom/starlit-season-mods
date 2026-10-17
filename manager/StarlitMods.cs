// Copyright (c) 2026 AlphaBoom. MIT licensed.
// Mod manager for THE IDOLM@STER STARLIT SEASON (Steam v1.61).
// Lives in the game root next to StarlitSeason.exe; its data is in StarlitModsData.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
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
    throw new IOException("请把压缩包解压到游戏根目录（含 StarlitSeason.exe 的文件夹），再打开 StarlitMods.exe。\n\n在 Steam 中右键游戏 → 管理 → 浏览本地文件 即可打开该目录。");
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
    throw new IOException("请先关闭游戏，再修改 Mod。");
  }
  void EnsureGame() {
   if (!HashIs(Under(Bin, "StarlitSeason-Win64-Shipping.exe"), Manifest.GameExeSha256))
    throw new IOException("游戏版本与本 Mod 包不匹配（仅支持 Steam v1.61）。未修改任何文件。");
  }
  // Restores any missing or altered package file from the verified payload copy.
  void Deploy() {
   foreach (var f in Manifest.Files) {
    string source = Under(Payload, f.Path);
    if (!HashIs(source, f.Sha256)) throw new IOException("Mod 包文件损坏或不完整：" + f.Path + "\n请重新解压完整的 Release 压缩包。");
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
    if (!File.Exists(Api)) throw new IOException("找不到游戏的 steam_api64.dll。");
    if (smoke) {
     if (!File.Exists(ApiOriginal)) throw new IOException("缺少原始 steam_api64_o.dll，无法安全管理 DLC 解锁。请在 Steam 中验证游戏文件完整性后重试。");
    } else {
     // The current file is the game's own Steam API (possibly updated by Steam).
     File.Copy(Api, ApiOriginal, true);
     File.Copy(Under(Payload, "dlc/smoke_api64.dll"), Api, true);
    }
    File.Copy(Under(Payload, "dlc/SmokeAPI.config.json"), config, true);
   } else if (smoke) {
    if (!File.Exists(ApiOriginal)) throw new IOException("缺少原始 steam_api64_o.dll，无法恢复。请在 Steam 中验证游戏文件完整性。");
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
  public void Apply(bool auto, bool dialogue, bool dlc) {
   EnsureClosed(); EnsureGame();
   Deploy();
   File.WriteAllText(ModsTxt, SetMods(File.Exists(ModsTxt) ? File.ReadAllText(ModsTxt) : "", auto, dialogue), new UTF8Encoding(false));
   Dlc(dlc);
   WriteState(json.Serialize(new { Version = Manifest.Version, Auto = auto, Dialogue = dialogue, Dlc = dlc }));
  }
  public void Uninstall() {
   EnsureClosed();
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

 public sealed class ManagerForm : Form {
  readonly Manager manager;
  readonly CheckBox autoBox = new CheckBox(), dialogueBox = new CheckBox(), dlcBox = new CheckBox();
  readonly Label status = new Label();
  public ManagerForm(Manager m) {
   manager = m;
   Text = "星耀季节 Mod 管理器 " + m.Manifest.Version;
   ClientSize = new Size(640, 470);
   Font = new Font("Microsoft YaHei UI", 10);
   FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false;
   StartPosition = FormStartPosition.CenterScreen; BackColor = Color.FromArgb(246, 248, 252);
   Controls.Add(new Label { Text = "STARLIT SEASON  ·  MODS", Font = new Font("Segoe UI", 18, FontStyle.Bold), Bounds = new Rectangle(28, 22, 590, 42) });
   Controls.Add(new Label { Text = "勾选要启用的功能，点击“应用”。修改前请关闭游戏，之后从 Steam 正常启动。", Bounds = new Rectangle(30, 70, 590, 30) });
   AddOption(autoBox, "对话自动 / 手动切换", "对话中按 手柄 Y / △ 或 键盘 A 切换；提示栏显示 AUTO ON / OFF。", 112);
   AddOption(dialogueBox, "对话存读档增强", "对话菜单增加 セーブ / ロード；独立 QUICK 存档位；F5 快存、F6 快读。", 187);
   AddOption(dlcBox, "DLC 解锁（SmokeAPI）", "关闭时恢复游戏原有的 Steam API 文件。", 262);
   var apply = new Button { Text = "应用", Bounds = new Rectangle(30, 345, 150, 42) };
   apply.Click += (s, e) => Run(() => manager.Apply(autoBox.Checked, dialogueBox.Checked, dlcBox.Checked), "已应用，下次启动游戏生效。");
   var uninstall = new Button { Text = "卸载全部 Mod", Bounds = new Rectangle(195, 345, 150, 42) };
   uninstall.Click += (s, e) => {
    if (MessageBox.Show(this, "卸载本包安装的全部 Mod 和加载器，并恢复原有 Steam API？\n\n存档（包括 QUICK 存档位）会保留。", "卸载 Mod", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes)
     Run(manager.Uninstall, "已卸载。可删除 StarlitMods.exe 和 StarlitModsData 文件夹；重新点“应用”可再次安装。");
   };
   var folder = new Button { Text = "打开游戏目录", Bounds = new Rectangle(360, 345, 150, 42) };
   folder.Click += (s, e) => Process.Start("explorer.exe", manager.Root);
   Controls.Add(apply); Controls.Add(uninstall); Controls.Add(folder);
   status.Bounds = new Rectangle(30, 400, 590, 56); status.ForeColor = Color.FromArgb(55, 76, 95);
   Controls.Add(status);
   Shown += (s, e) => {
    if (manager.FirstRun) Run(() => manager.Apply(true, true, true), "首次运行：已按默认配置启用全部功能。");
    else Run(() => { }, "已读取当前状态。");
   };
  }
  void AddOption(CheckBox box, string title, string detail, int y) {
   box.Text = title; box.Bounds = new Rectangle(32, y, 580, 29); Controls.Add(box);
   Controls.Add(new Label { Text = detail, ForeColor = Color.DimGray, Bounds = new Rectangle(55, y + 31, 560, 28) });
  }
  void Run(Action work, string message) {
   try { work(); status.Text = message; }
   catch (Exception ex) { status.Text = "操作未完成。"; MessageBox.Show(this, ex.Message, "Mod 管理器", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
   var st = manager.Read();
   autoBox.Checked = st.Auto; dialogueBox.Checked = st.Dialogue; dlcBox.Checked = st.Dlc;
   if (!st.GameMatches) status.Text += "\n注意：游戏版本不是本包支持的 Steam v1.61。";
   else if (!st.Loader) status.Text += "\n加载器未安装：点击“应用”安装。";
  }
 }

 public static class Program {
  [STAThread]
  public static int Main(string[] args) {
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
    if (cli) Console.Error.WriteLine(ex.Message); else MessageBox.Show(ex.Message, "Mod 管理器", MessageBoxButtons.OK, MessageBoxIcon.Error);
    return 1;
   }
  }
 }
}
