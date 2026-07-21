# docker-kit

本地开发用的 docker-compose 工具箱，一个服务一个 compose 文件，按需启动。

## 先决条件

需要 Docker Engine + Compose plugin。Linux 服务器可用仓库自带脚本一键装：

```bash
sudo bash scripts/install-docker.sh              # 交互式
sudo bash scripts/install-docker.sh -y --mirror cn   # 国内网络 + 自动化
```

支持 Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora。详情见 [docs/install-docker.md](docs/install-docker.md)。macOS / Windows 请装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。

**小内存机器（≤ 8GB）建议加 swap 兜底**，防止 JVM 服务（nexus / ES）启动峰值撞满 RAM 被 OOM Kill：

```bash
sudo bash scripts/init-swap.sh                       # 默认 2G swap + swappiness=10
sudo SWAP_SIZE_GB=4 bash scripts/init-swap.sh        # 自定义大小
```

幂等，重复跑安全。swappiness=10 意味着只有物理内存快满时才用 swap，日常不影响性能。

## 目录结构

```
docker-kit/
├── certs/                       # 共享 TLS 证书（nginx、elasticsearch、kibana 等复用）
│   ├── server.crt               # fullchain（leaf + intermediate + root）
│   ├── server.key
│   └── ca/
│       └── public-ca.crt        # intermediate + root（由 acme.sh --ca-file 生成，备用）
├── env/                         # 每个服务的环境变量
│   ├── consul.env
│   ├── elasticsearch.env
│   ├── kafka.env
│   ├── kibana.env
│   ├── mysql.env
│   ├── nexus.env
│   ├── solr.env
│   └── solr_zk.env
├── nginx/
│   ├── templates/               # nginx 反代模板（envsubst 后输出到 /etc/nginx/conf.d/）
│   └── snippets/                # ssl.conf / proxy-headers.conf
├── elasticsearch/
│   ├── plugins/                 # ES 插件（挂载到容器 /usr/share/elasticsearch/plugins）
│   │   ├── analysis-icu/
│   │   ├── analysis-ik/
│   │   ├── analysis-kuromoji/
│   │   ├── analysis-nori/
│   │   └── fastfilter-elasticsearch-plugin/
│   ├── config/
│   │   └── analysis/            # 用户词典 / 连字模式（挂到容器 config/analysis/）
│   ├── pipelines/               # ingest pipeline 定义（es-bootstrap.sh 导入）
│   └── data/                    # ES 索引数据（gitignore）
├── <service>/data/              # 每个有状态服务的持久化目录（gitignore，见"数据持久化"章节）
├── docker-compose-consul.yml
├── docker-compose-elasticsearch.yml
├── docker-compose-h2.yml
├── docker-compose-kafka.yml
├── docker-compose-mysql.yml
├── docker-compose-nexus.yml
├── docker-compose-nginx.yml
├── docker-compose-solr.yml
├── docs/
│   └── install-docker.md        # 安装 Docker / Compose 的详细指南
└── scripts/
    ├── check-certs.sh          # 检查 TLS 证书有效期 / 私钥匹配（macOS + Linux 兼容）
    ├── create-network.sh       # 创建所有独立 compose 共用的 Docker external network
    ├── es-bootstrap.sh          # ES 首启后的初始化：重置密码 + 导入 pipeline（幂等）
    ├── init-swap.sh             # 小内存机器创建 swap 文件（幂等）
    └── install-docker.sh        # 一键安装 Docker + Compose（Debian/Ubuntu/CentOS/RHEL/Fedora）
```

## Docker 网络

本仓库采用“一个服务一个 compose 文件”的方式管理服务。为了让不同 compose 文件启动的容器可以通过服务名互相访问，所有服务统一接入同一个 Docker external network：

```text
docker-kit-network
```

首次启动任意服务前，先创建公共网络：

```bash
bash scripts/create-network.sh
```

脚本是幂等的：网络已存在时不会重复创建。也可以手动执行等价命令：

```bash
docker network create docker-kit-network
```

统一网络后的访问规则：

- **容器访问容器**：使用 `服务名:容器内部端口`，例如 `mysql:3306`、`nexus:8081`、`nginx:80`
- **宿主机访问容器**：使用 `localhost:宿主机映射端口`，端口来自根目录 [.env](.env)
- **容器访问宿主机服务**：才使用 `host.docker.internal`

例如 nginx 反代 Nexus 时使用 Docker 内部 DNS 解析服务名：

```nginx
resolver 127.0.0.11 valid=30s;
set $upstream_nexus http://nexus:8081;
```

其中 `nexus:8081` 只有在 nginx 和 nexus 都接入 `docker-kit-network` 后才能正常工作。

## 端口管理

所有宿主端口集中定义在根目录 [.env](.env)，各 compose 文件通过 `${...}` 变量引用；docker-compose 会自动读取同目录 `.env`，改端口只改一处。

**当前分配**

| 服务 | 变量 | 宿主端口 | 容器端口 | 用途 |
|------|------|:-:|:-:|------|
| nginx | `NGINX_HTTP_PORT` / `NGINX_HTTPS_PORT` | 80 / 443 | 80 / 443 | HTTP / HTTPS |
| consul | `CONSUL_HTTP_PORT` | 8500 | 8500 | Web UI & API |
|        | `CONSUL_DNS_PORT` | 8600 | 8600 | DNS |
|        | `CONSUL_SERVER_RPC_PORT` | 8300 | 8300 | Server RPC |
|        | `CONSUL_SERF_LAN_PORT` | 8301 | 8301 | Serf LAN |
|        | `CONSUL_SERF_WAN_PORT` | 8302 | 8302 | Serf WAN |
| mysql | `MYSQL_PORT` | 3306 | 3306 | JDBC |
| nexus | `NEXUS_HTTP_PORT` | 8081 | 8081 | Web UI / Maven |
|       | `NEXUS_DOCKER_PORT` | 8085 | 8085 | Docker Registry |
| solr | `SOLR_HTTP_PORT` | 8983 | 8983 | Solr UI |
|      | `SOLR_ZK_PORT` | 2182 | 2181 | Solr Zookeeper |
| kafka | `KAFKA_PORT` | 9092 | 9092 | Kafka (KRaft，无外部 ZK) |
| elasticsearch | `ELASTICSEARCH_HTTP_PORT` | 9200 | 9200 | REST |
|               | `ELASTICSEARCH_TRANSPORT_PORT` | 9300 | 9300 | 节点间通信 |
| kibana | `KIBANA_PORT` | 5601 | 5601 | Web UI |
| h2 | `H2_TCP_PORT` | 9093 | 1521 | JDBC |
|    | `H2_WEB_PORT` | 8082 | 81 | Web Console |
| danmu-server | `DANMU_SERVER_PORT` | 7768 | 7768 | Misaka 弹幕 API |

**改端口**

编辑 [.env](.env)，然后重建对应服务：

```bash
docker compose -f docker-compose-<service>.yml up -d --force-recreate
```

**查看当前实际端口**

```bash
docker compose -f docker-compose-<service>.yml config | grep -E 'published|target'
```

## 域名管理

对外域名 / 主机名同样集中在 [.env](.env)：

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `BASE_DOMAIN` | `zaqbest.com` | 基础域名 |
| `NEXUS_HOSTNAME` | `nexus.zaqbest.com` | nginx `server_name`，反代到 nexus 容器 |
| `DANMU_HOSTNAME` | `danmu.zaqbest.com` | nginx `server_name`，反代到 danmu-server 容器 |
| `KAFKA_HOSTNAME` | `kafka.zaqbest.com` | Kafka `advertised.listeners`，客户端连接用 |

**nginx**：反代配置放在 [nginx/templates/*.template](nginx/templates/)，容器启动时 nginx 官方镜像自动 `envsubst` 生成 `/etc/nginx/conf.d/*.conf`。只有 `NGINX_ENVSUBST_FILTER_VARIABLES` 白名单里的变量会被替换，nginx 自身的 `$host` / `$request_uri` 等不受影响。新增反代域名步骤：

1. 在 [.env](.env) 加 `XXX_HOSTNAME=xxx.zaqbest.com`
2. 在 [docker-compose-nginx.yml](docker-compose-nginx.yml) 的 `environment:` 里把变量传进去，并追加到 `NGINX_ENVSUBST_FILTER_VARIABLES`
3. 在 [nginx/templates/](nginx/templates/) 新建 `xxx.conf.template`，用 `${XXX_HOSTNAME}` 引用
4. `docker compose -f docker-compose-nginx.yml up -d --force-recreate`

**kafka**：`KAFKA_ADVERTISED_LISTENERS` 从 compose 的 `environment:` 注入，而不是写死在 [env/kafka.env](env/kafka.env)。

**本机访问**：这些域名指向宿主机，需要在 macOS 的 `/etc/hosts` 加：

```
127.0.0.1  nexus.zaqbest.com danmu.zaqbest.com kafka.zaqbest.com
```

## 证书

`certs/server.crt` + `server.key` 是 `*.zaqbest.com` 通配符证书（Let's Encrypt 签发，有效期 90 天），所有需要 TLS 的服务共用同一套：

- **nginx**：挂载到 `/etc/nginx/certs/`，在 `nginx/snippets/ssl.conf` 里引用。
- **elasticsearch**：挂载到 `/usr/share/elasticsearch/config/certs/`，开启 HTTP TLS。
- **kibana**：挂载到 `/usr/share/kibana/config/certs/`，同时用作自己的 HTTPS 证书，连 ES 时走 Node.js 系统信任库校验。

`certs/ca/public-ca.crt` 是同一次 `acme.sh --install-cert --ca-file` 顺手落下来的 CA 束（intermediate + root），当前未在配置里引用，留着备用（内网严格审计场景可以塞进 `ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES`）。

### 签发 / 续期（acme.sh + Cloudflare DNS-01）

一次性安装 acme.sh：

```bash
curl -sSfL https://get.acme.sh | sh -s email=你的邮箱
```

配置 Cloudflare API Token（推荐，比 Global API Key 权限窄）：

```bash
# 在 https://dash.cloudflare.com/profile/api-tokens 建 Custom Token
#   权限：Zone.Zone:Read + Zone.DNS:Edit
#   Zone Resources：Include Specific zone zaqbest.com
export CF_Token='你的_API_Token'
export CF_Account_ID='你的_Cloudflare_Account_ID'
```

签发（首次）：

```bash
acme.sh --register-account -m 你的邮箱 --server letsencrypt

acme.sh --issue --dns dns_cf \
  -d zaqbest.com -d '*.zaqbest.com' \
  --keylength 2048 \
  --server letsencrypt
```

安装到本仓库，并配好续期后的自动 reload —— **只需要跑一次**，之后 acme.sh 自己写的 crontab 会每天检查并自动续、自动重启：

```bash
cd /path/to/docker-kit

acme.sh --install-cert -d zaqbest.com \
  --key-file       "$(pwd)/certs/server.key" \
  --fullchain-file "$(pwd)/certs/server.crt" \
  --ca-file        "$(pwd)/certs/ca/public-ca.crt" \
  --reloadcmd      "cd $(pwd) && \
                    docker compose -f docker-compose-elasticsearch.yml restart kibana elasticsearch && \
                    docker compose -f docker-compose-nginx.yml    restart nginx"
```

> ⚠️ acme.sh 用 **域名后缀** 区分密钥类型：`--keylength 2048/3072/4096` 存到 `~/.acme.sh/zaqbest.com/`，ECC（默认）存到 `~/.acme.sh/zaqbest.com_ecc/`。查询/安装/续期时**不加 `--ecc` 就是 RSA，加 `--ecc` 就是 ECC**，混用容易查到旧的那份。

### 有效期检查

用 [scripts/check-certs.sh](scripts/check-certs.sh) 随时查剩余天数：

```bash
./scripts/check-certs.sh              # 详细输出（subject / issuer / SAN / 私钥是否匹配）
./scripts/check-certs.sh --quiet      # 一行结果，适合塞进 shell rc / crontab
WARN_DAYS=45 ./scripts/check-certs.sh # 自定义提醒阈值（默认 30 天）
```

退出码：`0` 健康 · `1` 需要续期 · `2` 已过期或读取失败。

进入警戒区时脚本会打印完整的续期命令；一般不需要手工干预 —— acme.sh 的 crontab 会自动续期并按 `--reloadcmd` 重启相关服务。

## 数据持久化

有状态服务的数据都通过 bind mount 落到宿主机的**服务自己的 `data/` 子目录**下，[.gitignore](.gitignore) 已按服务逐条忽略。容器重建（`docker compose up -d --force-recreate`）、`docker compose down` 数据都保留；只有 `rm -rf <service>/data/` 或换工作目录才会丢。

| 服务 | 宿主机路径 | 容器路径 |
|------|-----------|---------|
| elasticsearch | `elasticsearch/data` | `/usr/share/elasticsearch/data` |
| mysql | `mysql/data` | `/var/lib/mysql` |
| nexus | `nexus/data` | `/nexus-data` |
| consul | `consul/data` `consul/config` | `/consul/data` `/consul/config` |
| kafka | `kafka/data` | `/bitnami/kafka` |
| h2 | `h2/data` | `/opt/h2-data` |
| solr | `solr/data` | `/var/solr` |
| solr_zk | `solr/zk/data` `solr/zk/datalog` | `/data` `/datalog` |

无状态服务（nginx / kibana）不需要持久化 —— Kibana 状态存 ES 的 `.kibana*` 索引里，随 ES 数据一起备份。

**离线备份**（简单，需停容器保证一致性）：

```bash
docker compose -f docker-compose-<service>.yml stop <service>
tar czf backup-<service>-$(date +%Y%m%d).tgz <service>/data/
docker compose -f docker-compose-<service>.yml start <service>
```

## 服务启动

首次启动服务前，请先创建所有独立 compose 共用的 Docker 网络：

```bash
bash scripts/create-network.sh
```

之后各服务可以按需单独启动。

### Nginx

```bash
docker compose -f docker-compose-nginx.yml up -d
```

nginx 已接入 `docker-kit-network`，可以通过服务名反代同一网络里的其他容器，例如 `nexus:8081`。在 `nginx/templates/` 下加 `.conf.template` 即可接入新的反代域名。

### Elasticsearch + Kibana（8.19.14）

单节点，开启 HTTP TLS + 账号密码，Kibana 走内置 `kibana_system` 服务账号连 ES。

**首次启动**

```bash
# 1. 启动 ES + Kibana
docker compose -f docker-compose-elasticsearch.yml up -d

# 2. 跑一次 bootstrap：等 ES 就绪 → 重置 kibana_system 密码 → 导入 pipeline
bash scripts/es-bootstrap.sh
```

`es-bootstrap.sh` 是**幂等**的，每次重装或清了 `elasticsearch/data/` 之后都可以再跑一次，不会破坏已有状态。它会：

1. 探活等 ES 就绪
2. 把 `kibana_system` 密码同步到 `env/kibana.env` 里的值（走 API，不走 CLI，避开容器间 TLS 主机名校验的坑）
3. 把 [elasticsearch/pipelines/*.json](elasticsearch/pipelines/) 全部导入为 ingest pipeline（文件名即 pipeline id）

**新增 pipeline**：在 [elasticsearch/pipelines/](elasticsearch/pipelines/) 放一个 `<name>.json` 文件，内容是 pipeline body（不包含最外层的名字键），重跑 `bash scripts/es-bootstrap.sh` 即可。

**访问**

| 服务   | 地址                     | 账号     | 密码     |
| ------ | ------------------------ | -------- | -------- |
| ES     | https://localhost:9200   | elastic  | elastic  |
| Kibana | https://localhost:5601   | elastic  | elastic  |

**已安装的插件**

`elasticsearch/plugins/` 目录直接挂载到容器 `/usr/share/elasticsearch/plugins`，ES 启动时自动加载：

- `analysis-icu` — ICU 分词、归一化（官方）
- `analysis-ik` — 中文 IK 分词（第三方，`ik_smart` / `ik_max_word`）
- `analysis-kuromoji` — 日语分词（官方）
- `analysis-nori` — 韩语分词（官方）
- `fastfilter-elasticsearch-plugin` — RoaringBitmap 大整数集合过滤（第三方）

要新增/移除插件：把整个插件目录放入或删出 `elasticsearch/plugins/`，重启 ES 即可。插件版本必须与 ES 版本严格匹配（都必须是 8.19.14）。

**用户词典与连字规则**

[elasticsearch/config/analysis/](elasticsearch/config/analysis/) 挂载到容器 `config/analysis/`，供各种 analyzer 引用：

- `userdict_ja.txt` — Kuromoji 日语用户词典
- `<lang>_word_list.txt` + `<lang>_hyphenation_patterns.xml` — 丹麦语 / 荷兰语 / 德语 / 挪威语 / 瑞典语的复合词分解词典和连字模式，配合 [Hyphenation Decompounder](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-hyp-decomp-tokenfilter.html) token filter 使用

在 mapping 里引用时使用相对路径（相对 `config/`），例如：

```json
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "kuromoji_user_dict": {
          "type": "kuromoji_tokenizer",
          "user_dictionary": "analysis/userdict_ja.txt"
        }
      },
      "filter": {
        "german_decompounder": {
          "type": "hyphenation_decompounder",
          "word_list_path": "analysis/german_word_list.txt",
          "hyphenation_patterns_path": "analysis/german_hyphenation_patterns.xml"
        }
      }
    }
  }
}
```

**验证插件加载 / 分词**

```bash
# 列出所有已加载插件
curl -sk -u elastic:elastic 'https://localhost:9200/_cat/plugins?v'

# 测试 IK 中文分词
curl -sk -u elastic:elastic -X POST 'https://localhost:9200/_analyze' \
  -H 'Content-Type: application/json' \
  -d '{"analyzer":"ik_smart","text":"中华人民共和国国歌"}'
```

- 网页登录 Kibana 用 `elastic` 超管账号（密码来自 `env/elasticsearch.env` 的 `ELASTIC_PASSWORD`）。
- Kibana 后台自己用 `kibana_system` 服务账号连 ES，密码来自 `env/kibana.env`。**8.x 禁止用 `elastic` 账号让 Kibana 连 ES**，必须走 `kibana_system` 或 service account token。

**重置 / 换密码**

- `ELASTIC_PASSWORD` 只在数据目录（`elasticsearch/data/`）为空的**首启**时生效，改完 env 重启不会同步已有实例。
- 要换 `elastic` 密码：
  ```bash
  curl -k -u elastic:<旧密码> -X POST \
    https://localhost:9200/_security/user/elastic/_password \
    -H 'Content-Type: application/json' \
    -d '{"password":"<新密码>"}'
  ```
- 要完全从头来：
  ```bash
  docker compose -f docker-compose-elasticsearch.yml down
  rm -rf elasticsearch/data
  # 重新按"首次启动"步骤
  ```

**改用 service account token（可选，更规范）**

如果不想跑 `reset-password`，可以用 service account token：

```bash
# ES 首启后跑一次，生成 token
docker compose -f docker-compose-elasticsearch.yml exec elasticsearch \
  bin/elasticsearch-service-tokens create elastic/kibana docker-kit
# 输出: SERVICE_TOKEN elastic/kibana/docker-kit = AAEAAWVsYXN0...
```

把 `env/kibana.env` 里的 `ELASTICSEARCH_USERNAME/PASSWORD` 两行删掉，换成：

```
ELASTICSEARCH_SERVICEACCOUNTTOKEN=<上面输出的 token>
```

之后 token 长期有效，不用再 reset。

### 其他服务

```bash
bash scripts/create-network.sh

docker compose -f docker-compose-consul.yml       up -d
docker compose -f docker-compose-h2.yml           up -d
docker compose -f docker-compose-kafka.yml        up -d
docker compose -f docker-compose-mysql.yml        up -d
docker compose -f docker-compose-nexus.yml        up -d
docker compose -f docker-compose-solr.yml         up -d
```

各服务的环境变量在 `env/*.env` 里，按需修改。

### MySQL 与 Danmu Server 连接说明

`danmu-server` 和 `mysql` 都接入 `docker-kit-network`，因此应用容器内访问 MySQL 使用服务名和容器内部端口：

```yaml
DANMUAPI_DATABASE__HOST=mysql
DANMUAPI_DATABASE__PORT=3306
```

不要在容器间通信里使用 `${MYSQL_PORT}` 或 `host.docker.internal`。`${MYSQL_PORT}` 是宿主机映射端口，主要给宿主机访问 MySQL 使用。

如果遇到类似下面的错误：

```text
asyncmy.errors.OperationalError: (2013, 'Lost connection to MySQL server during query')
```

优先检查 MySQL 是否重启、OOM 或连接超时：

```bash
docker compose -f docker-compose-mysql.yml logs --tail=200 mysql
docker inspect mysql --format '{{.State.OOMKilled}}'
docker compose -f docker-compose-danmu-server.yml exec danmu-server sh -lc 'getent hosts mysql && nc -vz mysql 3306'
docker compose -f docker-compose-mysql.yml exec mysql mysqladmin ping -uroot -p
```

当前 MySQL compose 已按 4G+ 服务器做了较稳妥的参数配置，包括 `512M` InnoDB buffer pool、`1g` 容器内存限制、较大的 `max_allowed_packet`，以及更宽松的 MySQL 网络读写/空闲超时。

修改 MySQL 参数后需要重建 MySQL 容器生效：

```bash
docker compose -f docker-compose-mysql.yml up -d --force-recreate
docker compose -f docker-compose-danmu-server.yml up -d --force-recreate
```

容器间互访请优先使用服务名和容器内部端口，例如：

| 目标服务 | 容器内访问地址 |
|---|---|
| mysql | `mysql:3306` |
| nexus | `nexus:8081` |
| nginx | `nginx:80` / `nginx:443` |
| elasticsearch | `elasticsearch:9200` |
| kibana | `kibana:5601` |
| solr | `solr:8983` |
| kafka | `kafka:9092` |
| consul | `consul:8500` |
| h2 | `h2:1521` |
| danmu-api | `danmu-api:9321` |

### Solr 首次启动

Solr 官方镜像的 `/var/solr` 目录里带了初始化种子（`solr.xml`、`zoo.cfg` 等），bind mount 一个空目录到 `/var/solr` 会遮住这些种子文件，导致 `Solr home directory /var/solr/data not found!`。首次启动前需要从镜像里**播种**一次：

```bash
# 1. 从镜像拷出 /var/solr 内容到宿主机的挂载点
docker run --rm -v $(pwd)/solr/data:/target solr:8.11.2 \
  bash -c 'cp -a /var/solr/. /target/'

# 2. 正常启动
docker compose -f docker-compose-solr.yml up -d
```

Solr Web UI：http://198.18.0.1:8983/solr/（compose 里 `command` 把 host 绑定成 `198.18.0.1`；宿主机可访问）。

Zookeeper 端不需要播种，官方镜像会自动初始化空 `/data` 目录。

### H2 数据库

- 数据持久化到 `h2/data/`
- 默认账号：`SA` / （密码为空）
- TCP (JDBC) 端口：`9093`（见 `.env` 的 `H2_TCP_PORT`）
- Web Console：http://localhost:8082（见 `.env` 的 `H2_WEB_PORT`）

**JDBC 连接串示例**

```
# 通过 TCP 服务连接（容器内数据文件名 test，可在 Web Console 首次连接时随意起名）
jdbc:h2:tcp://localhost:9093/./test
# 用户名 SA，密码留空
```

**Web Console 使用**

浏览器打开 http://localhost:8081，JDBC URL 填 `jdbc:h2:/opt/h2-data/<数据库名>`（例如 `jdbc:h2:/opt/h2-data/test`），User Name 填 `SA`，Password 留空，点 Connect。数据库文件会创建在容器内的 `/opt/h2-data`，映射到宿主 `h2/data/`。

