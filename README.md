# organize – 文件自动整理工具

[![Build](https://github.com/yourusername/organize/actions/workflows/build.yml/badge.svg)](https://github.com/yourusername/organize/actions/workflows/build.yml)

根据扩展名规则自动整理指定目录中的文件，支持自定义规则、模拟运行、临时文件清理。

## 功能特性

- 📁 按扩展名自动分类移动文件
- 🎨 完全可自定义规则（支持多扩展名映射到同一目录）
- 🧹 自动清理临时文件（temp目录、_.tmp、_.cache等）
- 🔍 模拟运行模式（--dry-run）
- 📝 规则管理：添加、删除、查看、编辑
- 📦 支持打包为 deb 和 AUR 安装
- 🖥️ 跨平台 Linux（仅依赖 bash 和 coreutils）

## 安装

### Debian / Ubuntu

```bash
sudo dpkg -i organize_*_all.deb
```

### Arch Linux (AUR)

```bash
paru -S organize-git
```

> 需要先[安装`paru`](https://wiki.archlinuxcn.org/wiki/AUR_%E5%8A%A9%E6%89%8B)

### 从源码安装

```bash
git clone https://github.com/yourusername/organize.git
cd organize
sudo make install
```

## 快速开始

```bash
# 首次使用，创建默认规则
organize --init

# 整理主目录
organize

# 整理下载目录并清理临时文件
organize -d ~/下载 --clean-temp

# 模拟运行（不实际移动）
organize --dry-run

# 添加新规则：将所有 .iso 文件移动到 ~/下载/镜像
organize --add iso 下载/镜像

# 查看当前规则
organize --show-rules

# 编辑规则文件
organize --edit-rules
```

## 配置文件

用户自定义规则保存在 `~/.config/organize/rules.conf`，格式：

```
扩展名1,扩展名2:目标目录（相对于 $HOME）
```

示例：

```
iso,img:下载/镜像
psd,psb:图片/Photoshop
```

## 开发与打包

```bash
make deb      # 构建 DEB 包
make clean    # 清理构建文件
```

## 许可证

MIT License
