# 对话存读档增强（DialogueMenu）

仅适用于 Windows Steam v1.61，使用 UE4SS 3.0.1-1170 加载。

## 功能

- 对话中按 Esc / 手柄菜单键打开的原生菜单，在「戻る」上方增加 **セーブする / ロードする**，
  直接进入游戏原生的存档 / 读档界面，选完后回到菜单。
- 新增独立的 **QUICK 存档位**，显示在 AUTO 存档下方。它和 AUTO、Slot 01–15 互不覆盖。
- 对话中 **F5 快速存档**到 QUICK 位，**F6 快速读档** QUICK 位。
- 游戏原生的存读档界面（标题 LOAD、地图 SYSTEM）同样显示 QUICK 位，可以手动存读。

读档后从游戏本身记录的检查点继续，和原生存档行为一致。

## 实现说明

- `Scripts/main.lua`：菜单按钮、QUICK 行、导航顺序（AUTO → QUICK → 01 …）、F5 / F6。
  所有 Unreal 调用都在同一个游戏线程定时器或钩子里执行。
- `native/dialogue-menu-native.c` → `DialogueMenu.dll`：
  - 调用游戏原生的存读档界面初始化，并在对话中暂停 / 恢复。
  - 存档以名称为键保存在 `MasterSaveData.GameSaveDataObjects`（`slot0` = AUTO，`slot1`–`slot15`）。
    DLL 在游戏的槽名表末尾追加 `slotQuick`（索引 16），再把一行原生槽位控件加入列表并调用原生的单槽初始化，
    因此 QUICK 位的显示、存档、读档、覆盖确认都走游戏自己的代码，并随 `MasterSave.sav` 一起保存。
  - 每个原生入口在调用前核对前 4 字节，游戏版本不符时拒绝执行。
- 卸载后 `slotQuick` 记录仍留在存档文件里，游戏不会读取它，不影响其他存档。

日志：`ue4ss/UE4SS.log`，搜索 `[DialogueMenu]`。
