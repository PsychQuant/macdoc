# Marketplace pin 更新紀錄

由 `scripts/marketplace-pins.sh update` 附加，一次更新一列，和 pin 的變更在同一個 commit。

- 日期是臺北時間。
- 「release commit」是上游 tag `v<新 binary>` 指向的 commit；三個 MCP plugin 的 submodule gitlink 也指向它。
- 第一列（2026-11-11）是腳本啟用前手動完成的更新，事後回填；那次一併帶入了沒同步的 4.9.0。

| 日期 | plugin | 舊 binary | 新 binary | release commit |
|---|---|---|---|---|
| 2026-11-11 | che-word-mcp | 4.8.0 | 4.10.0 | f89d287c71b49d51a5ebc6e86229a508a184bcc9 |
