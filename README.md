# path-favorites

Tern 路径收藏插件：在当前 tab 的分屏面板显示当前工作路径、搜索已收藏目录，并在新 tab 中打开收藏目录。

## 安装

```sh
tern plugin link ~/Documents/github/path-favorites
```

## 使用

- 状态栏的「收藏」按钮、palette，或 `ctrl+alt+shift+f`：在当前 tab 右侧打开路径面板。
- 面板顶部显示当前工作路径，并随终端焦点和路径变化更新。
 - 面板按钮「新增收藏」打开目录浏览器：进入子目录、用 `..` 返回上级，选择「收藏此目录」保存。
 - 「收藏当前路径」直接收藏面板显示的当前工作路径。

收藏数据保存在 Tern 的 `tern.kv` 中，插件重启后仍然保留。
