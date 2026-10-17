# 星耀季节 Mod 合集

《偶像大师 星耀季节》（THE IDOLM@STER STARLIT SEASON）的 Mod 合集，带一个开关管理器。

适用于 **Windows / Steam 版 v1.61**。

| Mod | 作用 |
| --- | --- |
| 对话自动 / 手动切换 | 对话中按 手柄 Y / △ 或键盘 A 切换自动播放，状态显示在原生提示栏。由 [独立仓库](https://github.com/AlphaBoom/starlit-season-text-auto-toggle) 维护。 |
| 对话存读档增强 | 对话菜单增加 セーブする / ロードする；独立的 QUICK 存档位（AUTO 下方）；F5 快存、F6 快读。详见 [说明](mods/DialogueMenu/README.md)。 |
| DLC 解锁 | 使用 [SmokeAPI](https://github.com/acidicoala/SmokeAPI) 4.1.3。 |

## 安装

1. **关闭游戏**。在 Steam 中右键游戏 → **管理 → 浏览本地文件**，打开游戏根目录（有 `StarlitSeason.exe` 的文件夹）。
2. 从 [Releases](https://github.com/AlphaBoom/starlit-season-mods/releases/latest) 下载 `StarlitSeasonMods-版本号.zip`，
   **解压到这个文件夹**（提示覆盖时选“是”）。
3. 双击 **`StarlitMods.exe`**。首次打开会自动启用全部功能（对话自动切换、存读档增强、DLC 解锁）。
4. 从 Steam 正常启动游戏。

解压后对话自动切换和存读档增强已经生效；DLC 解锁需要第 3 步，因为它要先备份游戏原有的 Steam API 文件。

## 开关与卸载

- 打开 **`StarlitMods.exe`**，勾选 / 取消功能后点 **应用**。下次启动游戏生效。
- 点 **卸载全部 Mod**：移除本包安装的 Mod 和加载器，恢复原有 Steam API。存档会保留（QUICK 存档也在存档文件里）。
  之后可以删除 `StarlitMods.exe` 和 `StarlitModsData` 文件夹。

更新时下载新版本，解压覆盖后再打开一次 `StarlitMods.exe` 点 **应用**。

如果 Steam“验证游戏文件完整性”恢复了 Steam API，DLC 解锁会显示为关闭，重新勾选并应用即可。

## 构建

Release 由 GitHub Actions（`.github/workflows/release.yml`）在推送 `v*` 标签时构建，本地也可以运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Version 1.0.0
```

依赖都固定版本并校验 SHA-256（`deps.json`）：UE4SS 3.0.1-1170（镜像在本仓库的 `deps-ue4ss-3.0.1-1170` Release，
上游 `experimental-latest` 已不再提供该文件）、SmokeAPI 4.1.3、对话自动切换仓库的固定提交、Zig 编译器（编译存读档 Mod 的原生 DLL）。

---

本仓库代码采用 [MIT 许可](LICENSE)。UE4SS 为 MIT 许可，SmokeAPI 为 Unlicense，许可文件随包附在 `StarlitModsData/licenses`。
游戏内容版权归游戏权利人所有。
