# GitHub 与 Gitee 发布流程

此文面向维护者。当前首发候选为 **v1.0.0**；[VERSION](VERSION) 与 [应用清单](Info.plist) 均为 1.0.0。文档修订号不用于应用标签。

## 仓库安排

已确认使用 [GitHub xiongwhu/RestReminder](https://github.com/xiongwhu/RestReminder) 作为公开主仓库，Gitee 同步相同源码与标签；Gitee 目标账号为 [dukexls](https://gitee.com/dukexls/projects)，同名镜像正在创建。首发版本为 v1.0.0，仅公开源码和标签，不创建二进制试用发行。实际仓库链接同步写入 [README](README.md)，镜像未就绪时明确标记。

- GitHub remote：`origin`。
- Gitee remote：`gitee`。
- 默认分支：`main`。
- 首发标签：`v1.0.0`，使用附注标签。
- 两个平台应指向同一提交；不使用会删除远端引用的 `git push --mirror`。
- GitHub Actions 只在 GitHub 运行；同步到 Gitee 不代表已有 Gitee 流水线。

## 发布前验证

从完整仓库根目录运行，使用可用的 Apple Command Line Tools / Xcode 和 macOS SDK：

```bash
./scripts/test.sh
python3 scripts/check-docs.py --package
BUILD_DIR="$PWD/build/release-validation" ARCHS=universal ./build.sh
BUILD_DIR="$PWD/build/release-validation" ./build.sh --verify-only
```

原生界面 smoke 采用独立模拟数据，准确命令见[技术设计](docs/design.md#93-界面与真实系统验证)。它们会显示窗口，由维护者在合适时运行；不自动操作真实历史、用户偏好或系统休眠。

确认版本、工作区和暂存内容后，再生成候选分发材料：

```bash
python3 scripts/prepare-release.py \
  --app "build/release-validation/歇一会儿.app"
```

打包器要求所有公开候选已加入 Git 暂存区、没有未暂存的跟踪文件或未忽略文件；它从实际 Git tree 生成源码，不从整个工作目录随意压缩。临时缓存、构建目录、用户历史、凭据及两张未使用且未记录来源的候选照片不应进入源码。

输出位于 `build/release/v1.0.0/`，包含：

- 对应源码 ZIP；
- macOS Universal ad-hoc 分发 ZIP，随附同一份源码、源码取得说明、CPAL 及照片来源；
- SHA-256 校验清单和版本/源码 tree 的构建记录；
- 另行生成的文档包与本版本发布说明。

分发包中的源码取得说明必须与实际版本一致。仓库尚未公开时，随包源码提供了直接取得方式；仓库确认后，发行说明再添加对应标签的实际链接。

## 确认版本与公开范围

创建发行提交和标签前，审阅候选 README、更新日志、源码文件清单、校验结果及分发材料，确认：

1. 目标 GitHub / Gitee 仓库、所有者与可见性；
2. 首发版本、提交署名及是否推送；
3. 是否创建平台发行记录、是否提供 ad-hoc 二进制下载。

当前二进制没有 Developer ID 签名或公证，不能标成已通过全部目标系统与硬件验收的正式安装包。首发可选择仅公开源码，或将二进制明确标为试用构建。源码许可与品牌署名见 [LICENSE](LICENSE)。

## 标签与双平台同步

确认后，以实际批准的地址配置两个 remote。将批准的提交与附注标签推送到两个平台：

```bash
git push -u origin main
git push origin v1.0.0
git push gitee main
git push gitee v1.0.0
```

发布后读取两个远端的分支和标签，核对 `main` 提交及 `v1.0.0^{}` 指向一致。若某个平台失败，保留成功记录并解决该平台的问题；不强制覆盖已有历史或重写公开标签。

平台发行说明使用 [更新日志](CHANGELOG.md) 的 1.0.0 章节，并明确 CPAL、素材来源、部署目标、ad-hoc 状态与验证边界。两个平台上传同一批文件，比较 SHA-256；不要上传个人历史、偏好、编译缓存、签名私钥或真实使用截图。

## 发布后

- 根据平台真实执行结果更新流水线状态，不预先添加“测试通过”徽章。
- 将 README 中的发布候选状态改为实际已发布状态，并补上真实下载和仓库链接。
- 保留来源、品牌署名、许可及对未知平台状态的说明。
