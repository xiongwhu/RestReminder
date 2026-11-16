# GitHub 与 Gitee 发布流程

当前发行版本为 **v1.0.1**，应用构建号为 **2**；[VERSION](VERSION) 与 [应用清单](Info.plist) 必须一致。文档修订号不用于应用标签。v1.0.0 首次公开源码；v1.0.1 起提供包含对应源码的 Universal DMG 和 ZIP。

## 仓库与发行范围

- [GitHub xiongwhu/RestReminder](https://github.com/xiongwhu/RestReminder) 为公开主仓库，remote 为 `origin`，默认分支为 `main`。
- [Gitee dukexls/RestReminder](https://gitee.com/dukexls/RestReminder) 为源码与发行附件镜像，remote 为 `gitee`；同步 `main` 和附注版本标签。
- 安装包与发行材料同时提供于 [Gitee 发行版 v1.0.1](https://gitee.com/dukexls/RestReminder/releases/tag/v1.0.1) 和 [GitHub Release v1.0.1](https://github.com/xiongwhu/RestReminder/releases/tag/v1.0.1)。发行说明和五个原始附件相同；Git 分支/标签与平台发行页面/附件分别同步，流水线仍仅在 GitHub 运行。
- 两个平台的同名分支和标签必须指向一致的对象；不强制覆盖已有版本，不使用 `git push --mirror`。

发布请求应明确版本范围、目标仓库和是否公开二进制。确认这些授权后，完成构建与候选材料验证，再提交、推送和发布；不把制作完成当作已经远程发布。

## 版本与更新说明

1. 按实际变更选择 SemVer；本轮可靠性修复与体验完善采用 `1.0.0 → 1.0.1`。
2. 同步修改 `VERSION`、`CFBundleShortVersionString` 和递增的 `CFBundleVersion`。
3. 在 [更新日志](CHANGELOG.md) 写明日期、核心修复、体验变化、安装方式与验证范围。
4. 将对应版本章节保存为 UTF-8 发行说明，供附注标签和 GitHub Release 使用同一份内容。
5. 核对 [README](README.md) 的下载入口、当前版本和安装说明；历史版本说明保留当时事实。

## 发布前验证

从完整仓库根目录运行，使用可用的 Apple Command Line Tools / Xcode 和 macOS SDK：

```bash
./scripts/test.sh
python3 -m unittest discover -s Tests -p 'test_release_packaging.py'
python3 scripts/check-docs.py
BUILD_DIR="$PWD/build/release-validation-v1.0.1" ARCHS=universal ./build.sh
./build.sh --verify-only "build/release-validation-v1.0.1/歇一会儿.app"
git diff --check
```

原生界面检查使用内存或合成数据，命令见 [技术设计](docs/design.md#93-界面与真实系统验证)。按改动范围选择检查；不操作真实历史、登录项或系统休眠。

必须为当前版本重新构建，不能将旧包重命名作为新版本。`--verify-only` 核对实际架构、部署目标和本地签名；最终打包还要比对应用版本、构建号、Bundle ID 与暂存源码清单。

## 生成 DMG 与对应源码

先审阅并暂存本次源码、测试、资源、版本和文档，确认所有候选都已进入 Git 索引，再运行：

```bash
python3 scripts/prepare-release.py \
  --app "build/release-validation-v1.0.1/歇一会儿.app" \
  --dmg
```

打包器要求没有未暂存的跟踪文件或未忽略文件，从实际 Git tree 导出源码，拒绝秘密文件、用户历史、签名凭据及未登记的候选照片。`--dmg` 为显式选项；省略时保持原有 ZIP 打包行为，CI 默认不创建或挂载磁盘映像。

输出位于 `build/release/v1.0.1/`，包含：

- `RestReminder-1.0.1-macos-universal.dmg`：应用及 Applications 拖拽安装入口，随附源码、安装说明、CPAL 和摄影来源；
- `RestReminder-1.0.1-source.zip`：与实际暂存 Git tree 精确对应的完整源码；
- `RestReminder-1.0.1-macos-universal-ad-hoc.zip`：同一应用和对应源码的 ZIP 分发包；
- `release-manifest.json`：版本、构建号、源码 tree、部署目标、签名状态和附件哈希；
- `SHA256SUMS`：发布材料 SHA-256 校验清单。

同版本输出目录已存在时，打包器拒绝覆盖。检查原有材料，使用独立目录开展额外验证；不要无检查地删除或替换已有发行物。

应用复制到独立 staging 后写入精确源码取得说明，再重新执行 ad-hoc 签名和全架构签名验证。源应用不被修改。DMG 中的应用、ZIP 中的应用、对应源码和 Git tree 必须相互一致。

## 安装包验收

1. 使用 `hdiutil verify` 校验 DMG，核对格式为压缩只读映像。
2. 将 DMG 只读挂载到项目 build 下的独立检查目录，使用 `-nobrowse`，不启动应用。
3. 检查应用、`Applications -> /Applications` 链接、源码 ZIP、许可、摄影来源和安装说明齐全。
4. 对挂载应用核对版本/构建号、`arm64 + x86_64`、部署目标和全部切片签名；核对源码 ZIP 哈希及清单中的 Git tree。
5. 将应用复制到另一个独立检查目录，验证复制后的签名和版本，模拟拖拽安装；不覆盖实际“应用程序”目录或用户当前版本。
6. 完成后卸载本次挂载；上传前检查 `SHA256SUMS`。

用户安装前先退出旧应用，打开 DMG 后将应用拖到 Applications，再从固定安装位置启动。当前构建没有 Developer ID 签名或 Apple 公证；首次启动可能被 macOS 拦截，应先核对来源与文件，再按“隐私与安全性”提示处理。不提供关闭系统整体安全保护的命令。

## 提交、标签与双平台同步

候选验证通过后，核对暂存内容再创建提交和附注标签。标签说明使用相同版本的更新日志，不重写已有公开标签：

```bash
git commit -m "chore: release v1.0.1"
git tag -a v1.0.1 -F build/release-notes-v1.0.1.md
git push origin main v1.0.1
git push gitee main v1.0.1
```

发行提交的 Git tree 必须等于 `release-manifest.json` 中的 `source_git_tree`。推送后读取两个远端的 `main`、附注标签对象和 `v1.0.1^{}`，核对一致性；某个平台失败时保留成功状态并处理该平台，不强制覆盖历史。

## GitHub Release 与发布后核对

远端标签存在后，通过 GitHub API、已认证 CLI 或网页创建该标签的 Release，使用同一份 UTF-8 发行说明，上传 DMG、源码 ZIP、应用 ZIP、构建清单和 SHA-256 文件。可先创建草稿，完成所有附件上传后再公开。

公开后读取 Release、标签和附件列表，核对版本、目标提交、文件名、大小、SHA-256 与下载入口。GitHub Actions 的运行状态以对应发布提交的真实结果为准；本地测试不等于远程绿色运行，也不等于 Apple 公证或 Intel/旧系统实机验收。

## Gitee 发行版与附件同步

Git 推送只同步源码和标签。Gitee 的发行版与附件需要另外发布；Git 推送凭据不一定能用于 Open API，使用带 `projects` 权限的短期访问令牌，或通过已登录网页操作。

1. 复用 GitHub 对应版本的标题、完整更新说明、原始版本标签和目标提交，不重新打包已有安装包，不移动公开标签。
2. 根据 [Gitee 官方 API](https://gitee.com/api/v5/swagger)，通过 `GET /api/v5/repos/{owner}/{repo}/releases/tags/{tag}` 检查发行版；不存在时，通过 `POST /api/v5/repos/{owner}/{repo}/releases` 创建。
3. 通过 `POST /api/v5/repos/{owner}/{repo}/releases/{release_id}/attach_files` 以 multipart 上传五个原始文件。已有附件先比对，避免重复或覆盖维护者已有内容。
4. 匿名读取发行页和下载链接，逐个下载附件并比对字节数及 SHA-256；不能只核对文件名或上传成功响应。
5. 令牌只在内存或权限为 `600` 的本机临时文件中使用；不写入仓库、发行说明、报告或日志，发布完成后删除临时文件。

v1.0.1 的 Gitee 发行 ID 为 `1315430`，指向提交 `65765cb056f8745f21ca83c3e12fb709ef1edef6`；五个附件已通过无需登录的下载及哈希比对。下载入口的后续文档提交不改变 v1.0.1 标签、对应源码树或安装包内容。

当前系统范围与隐私约定见 [README](README.md)，源码与素材许可见 [LICENSE](LICENSE) 和 [摄影来源](Resources/PHOTO-CREDITS.md)。
