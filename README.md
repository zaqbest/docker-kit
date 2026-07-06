# docker-kit

本地开发用的 docker-compose 工具箱，一个服务一个 compose 文件，按需启动。

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
│   ├── conf.d/                  # 各服务的反代配置
│   └── snippets/                # ssl.conf / proxy-headers.conf
├── elasticsearch/
│   └── plugins/                 # ES 插件（挂载到容器 /usr/share/elasticsearch/plugins）
│       ├── analysis-icu/
│       ├── analysis-kuromoji/
│       ├── analysis-nori/
│       └── fastfilter-elasticsearch-plugin/
├── data/                        # 持久化数据（gitignore）
├── docker-compose-consul.yml
├── docker-compose-elasticsearch.yml
├── docker-compose-kafka.yml
├── docker-compose-mysql.yml
├── docker-compose-nexus.yml
├── docker-compose-nginx.yml
└── docker-compose-solr.yml
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
# 1. 先启 ES（数据目录为空时，ELASTIC_PASSWORD 才会生效）
docker compose -f docker-compose-elasticsearch.yml up -d elasticsearch

# 2. 等 ES 就绪（约 20-30s），把 kibana_system 的密码设置成和 env 里一致
#    推荐用 API（自签证书 SAN 里没有容器 IP，reset-password CLI 会因主机名校验失败）
curl -k -u elastic:elastic -X POST \
  https://localhost:9200/_security/user/kibana_system/_password \
  -H 'Content-Type: application/json' \
  -d '{"password":"kibana_system"}'

# 3. 启动 Kibana
docker compose -f docker-compose-elasticsearch.yml up -d kibana
```

**访问**

| 服务   | 地址                     | 账号     | 密码     |
| ------ | ------------------------ | -------- | -------- |
| ES     | https://localhost:9200   | elastic  | elastic  |
| Kibana | https://localhost:5601   | elastic  | elastic  |

**已安装的插件**

`elasticsearch/plugins/` 目录直接挂载到容器 `/usr/share/elasticsearch/plugins`，ES 启动时自动加载：

- `analysis-icu` — ICU 分词、归一化（官方）
- `analysis-kuromoji` — 日语分词（官方）
- `analysis-nori` — 韩语分词（官方）
- `fastfilter-elasticsearch-plugin` — RoaringBitmap 大整数集合过滤（第三方）

要新增/移除插件：把整个插件目录放入或删出 `elasticsearch/plugins/`，重启 ES 即可。插件版本必须与 ES 版本严格匹配（都必须是 8.19.14）。

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
docker compose -f docker-compose-kafka.yml        up -d
docker compose -f docker-compose-mysql.yml        up -d
docker compose -f docker-compose-nexus.yml        up -d
docker compose -f docker-compose-solr.yml         up -d
```

各服务的环境变量在 `env/*.env` 里，按需修改。
