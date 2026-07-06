# 安装 Docker 与 Docker Compose

在一台干净的 Linux 服务器上跑起本仓库之前，先装好 Docker Engine 和 Compose plugin。仓库自带一键脚本 [scripts/install-docker.sh](scripts/install-docker.sh)。

## 支持的系统

- Debian 10/11/12
- Ubuntu 20.04 / 22.04 / 24.04
- CentOS 7 / 8 / Stream 9
- RHEL 8 / 9、Rocky、AlmaLinux
- Fedora（较新版本）
- Oracle Linux（作为 RHEL 系）

macOS / Windows 请直接安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)，脚本只面向 Linux。

## 一键安装

```bash
git clone <本仓库> docker-kit
cd docker-kit

sudo bash scripts/install-docker.sh
```

**参数**

| 参数 | 作用 |
|------|------|
| `-y` / `--yes` | 全部默认 yes（比如自动把当前用户加入 `docker` 组），适合脚本化 |
| `--mirror cn` | 用阿里云镜像下载 Docker 仓库和 GPG，中国大陆网络推荐 |
| `-h` / `--help` | 打印帮助 |

**示例**

```bash
# 中国大陆机器 + 全自动
sudo bash scripts/install-docker.sh -y --mirror cn
```

## 脚本做了什么

1. 检测发行版（读 `/etc/os-release`），归一到 `deb` 或 `rpm` 系
2. 卸载旧版 `docker` / `docker-engine` / `docker.io` / `podman-docker` 等冲突包
3. 添加 Docker 官方或阿里云镜像的 GPG 与仓库
4. 安装 `docker-ce` `docker-ce-cli` `containerd.io` `docker-buildx-plugin` `docker-compose-plugin`
5. `systemctl enable --now docker`
6. 跑一次 `docker run hello-world` 验证
7. 询问是否把当前用户加入 `docker` 组（免 sudo 用 docker）

## 手动安装

如果不愿意跑脚本，按官方文档：

- Debian / Ubuntu：<https://docs.docker.com/engine/install/ubuntu/>
- CentOS / RHEL：<https://docs.docker.com/engine/install/centos/>
- Fedora：<https://docs.docker.com/engine/install/fedora/>

关键点：装 `docker-compose-plugin` 而不是老的 `docker-compose`（Python 版），本仓库所有命令都是 `docker compose`（子命令，带空格），不是 `docker-compose`（连字符）。

## 常见问题

**加了 docker 组后还是要 sudo？**
注销后重新登录，或者临时用 `newgrp docker` 让当前 shell 生效。

**`hello-world` 拉不下来？**
说明网络出不去官方 registry。配置国内镜像加速器 [/etc/docker/daemon.json](https://cr.console.aliyun.com/cn-hangzhou/instances/mirrors)：

```json
{
  "registry-mirrors": ["https://<你的加速器地址>"]
}
```

然后 `sudo systemctl restart docker`。

**RHEL / CentOS 7 上包冲突（`podman` / `buildah`）？**
先 `sudo dnf remove podman buildah` 再重跑脚本。

**Ubuntu 上提示 `E: Package 'docker-ce' has no installation candidate`？**
通常是 codename 识别失败。检查 `lsb_release -cs`，Ubuntu 24.04 (`noble`) 需要较新版本的 `apt-get update` 后才能找到。脚本已经处理了这一步，如果仍失败，多半是网络问题。

## 验证

安装完成后：

```bash
docker --version
docker compose version
docker run --rm hello-world
```

三条都通过就可以回到 [README.md](README.md) 按服务清单启动了。
