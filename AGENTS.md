# 项目约束

## 文件处理

- 所有文件读写使用 UTF-8 编码，修改时不得改变原有编码。
- PowerShell 读取中文文件前，执行 `chcp 65001` 并设置 UTF-8 输出，使用 `Get-Content -Encoding UTF8`。
- 不得使用 sed/awk 处理中文文件，改用 Python 或 Node.js。
- 新增代码注释使用中文。

## 构建与发布

- 不得使用 GitHub Actions 构建；所有构建、打包和签名均在本机完成。
- 不得触发或重新启用本仓库的 GitHub Actions。2026-10-18 已在仓库设置禁用 Actions。
- 发布使用原正式证书，不得提交签名密钥、密码或访问令牌。
