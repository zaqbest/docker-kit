# docker-kit

本地开发用的 docker-compose 工具箱，一个服务一个 compose 文件，按需启动。

## 先决条件

需要 Docker Engine + Compose plugin。Linux 服务器可用仓库自带脚本一键装：

```bash
sudo bash scripts/install-docker.sh              # 交互式
sudo bash scripts/install-docker.sh -y --mirror cn   # 国内网络 + 自动化
```

支持 Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora。详情见 [docs/install-docker.md](docs/install-docker.md)。macOS / Windows 请装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。

## 目录结构

```
docker-kit/
├── certs/                       # 共享 TLS 证书（nginx、elasticsearch、kibana 复用）
│   ├── server.crt
│   └── server.key
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
│   └── pipelines/               # ingest pipeline 定义（es-bootstrap.sh 导入）
├── data/                        # 持久化数据（gitignore）
├── docker-compose-consul.yml
├── docker-compose-elasticsearch.yml
├── docker-compose-h2.yml
├── docker-compose-kafka.yml
├── docker-compose-mysql.yml
├── docker-compose-nexus.yml
├── docker-compose-nginx.yml
├── docker-compose-solr.yml
├── docker-compose-trojan-go.yml
├── docs/
│   └── install-docker.md        # 安装 Docker / Compose 的详细指南
└── scripts/
    ├── es-bootstrap.sh          # ES 首启后的初始化：重置密码 + 导入 pipeline（幂等）
    └── install-docker.sh        # 一键安装 Docker + Compose（Debian/Ubuntu/CentOS/RHEL/Fedora）
```

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
| kafka | `KAFKA_PORT` | 9092 | 9092 | Kafka |
|       | `KAFKA_ZK_PORT` | 2181 | 2181 | Kafka Zookeeper |
| elasticsearch | `ELASTICSEARCH_HTTP_PORT` | 9200 | 9200 | REST |
|               | `ELASTICSEARCH_TRANSPORT_PORT` | 9300 | 9300 | 节点间通信 |
| kibana | `KIBANA_PORT` | 5601 | 5601 | Web UI |
| h2 | `H2_TCP_PORT` | 9093 | 1521 | JDBC |
|    | `H2_WEB_PORT` | 8082 | 81 | Web Console |
| trojan-go | `TROJAN_GO_PORT` | 8443 | 443 | Trojan (TLS) |

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
| `KAFKA_HOSTNAME` | `kafka.zaqbest.com` | Kafka `advertised.listeners`，客户端连接用 |
| `TROJAN_GO_HOSTNAME` | `trojan.zaqbest.com` | Trojan-Go SNI，客户端需与之匹配 |

**nginx**：反代配置放在 [nginx/templates/*.template](nginx/templates/)，容器启动时 nginx 官方镜像自动 `envsubst` 生成 `/etc/nginx/conf.d/*.conf`。只有 `NGINX_ENVSUBST_FILTER_VARIABLES` 白名单里的变量会被替换，nginx 自身的 `$host` / `$request_uri` 等不受影响。新增反代域名步骤：

1. 在 [.env](.env) 加 `XXX_HOSTNAME=xxx.zaqbest.com`
2. 在 [docker-compose-nginx.yml](docker-compose-nginx.yml) 的 `environment:` 里把变量传进去，并追加到 `NGINX_ENVSUBST_FILTER_VARIABLES`
3. 在 [nginx/templates/](nginx/templates/) 新建 `xxx.conf.template`，用 `${XXX_HOSTNAME}` 引用
4. `docker compose -f docker-compose-nginx.yml up -d --force-recreate`

**kafka**：`KAFKA_ADVERTISED_LISTENERS` 从 compose 的 `environment:` 注入，而不是写死在 [env/kafka.env](env/kafka.env)。

**本机访问**：这些域名指向宿主机，需要在 macOS 的 `/etc/hosts` 加：

```
127.0.0.1  nexus.zaqbest.com kafka.zaqbest.com
```

## 证书

`certs/server.crt` + `server.key` 是自签证书，所有需要 TLS 的服务共用同一套：

- **nginx**：挂载到 `/etc/nginx/certs/`，在 `nginx/snippets/ssl.conf` 里引用。
- **elasticsearch**：挂载到 `/usr/share/elasticsearch/config/certs/`，开启 HTTP TLS。
- **kibana**：挂载到 `/usr/share/kibana/config/certs/`，用来校验 ES 证书。

## 服务启动

### Nginx

```bash
docker compose -f docker-compose-nginx.yml up -d
```

在 `nginx/conf.d/` 下加 `.conf` 即可接入新的反代域名。

### Elasticsearch + Kibana（8.19.14）

单节点，开启 HTTP TLS + 账号密码，Kibana 走内置 `kibana_system` 服务账号连 ES。

**首次启动**

```bash
# 1. 启动 ES + Kibana
docker compose -f docker-compose-elasticsearch.yml up -d

# 2. 跑一次 bootstrap：等 ES 就绪 → 重置 kibana_system 密码 → 导入 pipeline
bash scripts/es-bootstrap.sh
```

`es-bootstrap.sh` 是**幂等**的，每次重装或清了 `data/elasticsearch/` 之后都可以再跑一次，不会破坏已有状态。它会：

1. 探活等 ES 就绪
2. 把 `kibana_system` 密码同步到 `env/kibana.env` 里的值（走 API，不走 CLI，避开自签证书主机名校验的坑）
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

- `ELASTIC_PASSWORD` 只在数据目录（`data/elasticsearch/data/`）为空的**首启**时生效，改完 env 重启不会同步已有实例。
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
  rm -rf data/elasticsearch
  # 重新按"首次启动"步骤
  ```

**改用 service account token（可选，更规范）**

如果不想跑 `reset-password`，可以用 service account token：

```bash
# ES 首启后跑一次，生成 token
docker exec elasticsearch \
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
docker compose -f docker-compose-consul.yml       up -d
docker compose -f docker-compose-h2.yml           up -d
docker compose -f docker-compose-kafka.yml        up -d
docker compose -f docker-compose-mysql.yml        up -d
docker compose -f docker-compose-nexus.yml        up -d
docker compose -f docker-compose-solr.yml         up -d
docker compose -f docker-compose-trojan-go.yml    up -d
```

各服务的环境变量在 `env/*.env` 里，按需修改。

### H2 数据库

- 数据持久化到 `data/h2/`
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

浏览器打开 http://localhost:8081，JDBC URL 填 `jdbc:h2:/opt/h2-data/<数据库名>`（例如 `jdbc:h2:/opt/h2-data/test`），User Name 填 `SA`，Password 留空，点 Connect。数据库文件会创建在容器内的 `/opt/h2-data`，映射到宿主 `data/h2/`。

### Trojan-Go

Trojan 协议代理，把流量伪装成 TLS。镜像用社区常用的 [p4gefau1t/trojan-go](https://github.com/p4gefau1t/trojan-go)。

**首次使用**

1. 修改 [.env](.env) 里的 Trojan-Go 相关变量：
   - `TROJAN_GO_PASSWORD` — 必须换成强密码（默认是占位符）
   - `TROJAN_GO_HOSTNAME` — SNI 主机名，客户端要一致；默认 `trojan.zaqbest.com`
   - `TROJAN_GO_PORT` — 宿主机监听端口，默认 8443
   - `TROJAN_GO_FALLBACK_HOST` / `TROJAN_GO_FALLBACK_PORT` — 非 Trojan 流量转发去处（伪装网站）；默认转到本仓库的 nginx 容器
2. 保证证书 [certs/server.crt](certs/server.crt) / [certs/server.key](certs/server.key) 的 SAN 覆盖 SNI 主机名（当前证书是 `*.zaqbest.com` 通配）
3. 启动：
   ```bash
   docker compose -f docker-compose-trojan-go.yml up -d
   ```
4. 查看日志：
   ```bash
   docker logs -f trojan-go
   ```

**模板机制**

[trojan-go/config.template.json](trojan-go/config.template.json) 里用 `__XXX__` 占位符，容器启动时会 `sed` 替换成环境变量的值，写到 `/tmp/config.json` 再传给 trojan-go。修改 [.env](.env) 后 `docker compose -f docker-compose-trojan-go.yml up -d --force-recreate` 生效。

**fallback 说明**

trojan 协议要求配一个"伪装 web 站点"，任何不带正确密码的探测流量都会被静默转发到那里，让攻击者看起来像访问了一个普通网站。默认转发到本仓库的 nginx 容器（同 docker network），跑 nginx 时就能正常工作；如果只单独跑 trojan-go，把 `TROJAN_GO_FALLBACK_HOST` 改成公网站点（比如 `www.bing.com`）+ `PORT=443` 即可。

**端口**

宿主机 `${TROJAN_GO_PORT}`（默认 8443，见 [.env](.env)）→ 容器 443。如果服务器 443 空着且没被 nginx 占用，可以把 `.env` 里的 `TROJAN_GO_PORT` 改成 `443` 让协议更逼真。

**客户端配置要点**

| 字段 | 值 |
|------|-----|
| 服务器 | `${TROJAN_GO_HOSTNAME}`（默认 `trojan.zaqbest.com`） |
| 端口 | 8443（或你在 `.env` 里改的值） |
| 密码 | [.env](.env) 里的 `TROJAN_GO_PASSWORD` |
| SNI | 与服务端 `ssl.sni` 一致 |
| 跳过证书校验 | 自签证书需勾选；生产证书不需要 |

**用途提示**：本仓库把 Trojan-Go 放进来是为了在自己的服务器上快速拉起代理服务（个人科学上网、跨区域测试等合法用途）。请在符合当地法律与服务条款的前提下使用。
