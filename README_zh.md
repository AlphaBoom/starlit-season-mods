# 星耀季节 Mod 合集

[English](README.md) | 中文

《偶像大师 星耀季节》（THE IDOLM@STER STARLIT SEASON）的 Mod 合集，带一个开关管理器。

适用于 **Windows / Steam 版 v1.61**。

| Mod | 作用 |
| --- | --- |
| 对话自动 / 手动切换 | 对话中按 手柄 Y / △ 或键盘 A 切换自动播放，状态显示在原生提示栏。由 [独立仓库](https://github.com/AlphaBoom/starlit-season-text-auto-toggle) 维护。 |
| 对话存读档增强 | 对话菜单增加 SAVE / LOAD；独立的 QUICK 存档位（AUTO 下方）；F5 快存、F6 快读。详见 [说明](mods/DialogueMenu/README.md)。 |
| 语音卡住修复（实验性，默认关闭） | 对话语音偶发无声、自动推进停住时重新播放该句，仍不行则跳过。详见 [说明](mods/VoiceWatchdog/README.md)。 |
| DLC 解锁（默认关闭） | 使用 [SmokeAPI](https://github.com/acidicoala/SmokeAPI) 4.1.3，需要在管理器中手动开启。 |

## 功能一览

**对话菜单里的存读档。** 对话中按 Esc（手柄菜单键）打开的原生菜单，在「戻る」上方多了 SAVE / LOAD，
进入游戏原生的存档 / 读档界面。对话中的存档从该对话开始时游戏记录的检查点继续。

![对话菜单中的 SAVE / LOAD](docs/images/pause-menu.jpg)

**独立的 QUICK 存档位。** QUICK 位在 AUTO 下方，使用游戏自带的金色存档样式，和 AUTO、Slot 01–15 互不覆盖。
**F5** 存到 QUICK、**F6** 读取 QUICK：对话中可用，Home 和地图界面上只要游戏的 SYSTEM 菜单允许存档也可用。
标题画面的 LOAD、游戏内的存读档界面也能看到并手动使用它。

![读档界面：AUTO 下方的 QUICK 存档位](docs/images/quick-slot.jpg)

**对话自动 / 手动切换。** 键盘 A、手柄 Y / △ 切换，提示栏的图标跟随当前使用的设备（下图为键盘）。

![提示栏中的 A AUTO ON](docs/images/auto-keyboard.jpg)

**Mod 管理器。** 点卡片切换开关，点「应用」生效；「卸载全部 Mod」恢复原版。右上角可切换中文 / English。

![StarlitMods.exe](docs/images/manager.png)

## 安装

1. **关闭游戏**。在 Steam 中右键游戏 → **管理 → 浏览本地文件**，打开游戏根目录（有 `StarlitSeason.exe` 的文件夹）。
2. 从 [Releases](https://github.com/AlphaBoom/starlit-season-mods/releases/latest) 下载 `StarlitSeasonMods-版本号.zip`，
   **解压到这个文件夹**（提示覆盖时选“是”）。
3. 从 Steam 正常启动游戏。对话自动切换和存读档增强解压后即生效。

需要 DLC 解锁时，双击 **`StarlitMods.exe`**，打开「DLC 解锁」后点 **应用**。管理器会先备份游戏原有的 Steam API 文件。

## 开关与卸载

- 打开 **`StarlitMods.exe`**，点卡片切换功能后点 **应用**。下次启动游戏生效。
- 点 **卸载全部 Mod**：移除本包安装的 Mod 和加载器，恢复原有 Steam API。存档会保留（QUICK 存档也在存档文件里）。
  之后可以删除 `StarlitMods.exe` 和 `StarlitModsData` 文件夹。

更新时下载新版本，解压覆盖即可；已开启 DLC 解锁的，再打开一次 `StarlitMods.exe` 点 **应用**。

如果 Steam“验证游戏文件完整性”恢复了 Steam API，DLC 解锁会显示为关闭，重新开启并应用即可。

开发相关内容见 [构建与发布说明（英文）](docs/build.md)。

---

本仓库代码采用 [MIT 许可](LICENSE)。UE4SS 为 MIT 许可，SmokeAPI 为 Unlicense，许可文件随包附在 `StarlitModsData/licenses`。
游戏内容版权归游戏权利人所有。
