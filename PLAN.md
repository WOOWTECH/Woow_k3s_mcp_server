# K3s MCP Server 部署計畫

## 決策摘要

| 項目 | 決定 |
|------|------|
| 範圍 | Phase 1: 單叢集 in-cluster 模式 |
| 部署方式 | Helm chart 部署到 K3s cluster |
| Transport | HTTP+SSE（`/mcp` + `/sse`），共享服務 |
| 存取方式 | ClusterIP + port-forward |
| 權限 | 全開（非 read-only），可建立/修改/刪除資源 |
| Toolsets | `core`, `config`, `helm` |
| denied_resources | 只擋 `Secret` |
| Namespace | `mcp-system` |
| RBAC | 綁定 K8s 內建 `cluster-admin` ClusterRole（測試環境全開） |

## 實作步驟

### Step 1: 建立 namespace 與 values 檔案

建立 `mcp-system` namespace，撰寫 `values-woowtech.yaml`：

```yaml
ingress:
  enabled: false

serviceAccount:
  create: true
  name: kubernetes-mcp-viewer

rbac:
  create: true
  extraClusterRoleBindings:
    - name: mcp-full-access
      roleRef:
        name: cluster-admin
        external: true

extraArgs:
  - "--toolsets=core,config,helm"
  - "--log-level=2"

config:
  port: "8080"
  toolsets: ["core", "config", "helm"]
  log_level: 2

  [[denied_resources]]
  group: ""
  version: "v1"
  kind: "Secret"

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

> 注意：config section 的 denied_resources 是 TOML array-of-tables 語法，
> 需確認 Helm chart 的 ConfigMap template 是否正確處理。
> 若 chart 不支援 nested TOML，改用 extraVolumes 掛自訂 ConfigMap。

### Step 2: 用 Helm 安裝

```bash
kubectl create namespace mcp-system
helm upgrade -i kubernetes-mcp-server \
  oci://ghcr.io/containers/charts/kubernetes-mcp-server \
  -n mcp-system \
  -f values-woowtech.yaml
```

### Step 3: 驗證部署

```bash
kubectl -n mcp-system get pods
kubectl -n mcp-system logs deployment/kubernetes-mcp-server
```

### Step 4: 建立 port-forward 存取

```bash
kubectl -n mcp-system port-forward svc/kubernetes-mcp-server 8080:8080
```

驗證 MCP endpoint：
```bash
curl -s http://localhost:8080/healthz
```

### Step 5: 設定 Claude Code 連接

在 Claude Code settings 中加入 MCP server connector：
- URL: `http://localhost:8080/mcp`
- Transport: Streamable HTTP

### Step 6: 功能驗測

測試以下操作確認功能正常：
- 列出所有 namespace
- 列出特定 namespace 的 pods
- 查看 node 狀態
- 列出 Helm releases
- 建立/刪除測試資源（驗證寫入權限）
- 確認 Secret 被擋（denied_resources 生效）

## 需要注意的技術細節

1. **config.toml 中的 denied_resources**：Helm chart 的 `config:` section 直接映射到 config.toml。
   需測試 `denied_resources` 的 TOML array-of-tables 語法是否被 chart template 正確處理。
   若不行，需用獨立 ConfigMap + extraVolumes 掛載。

2. **RBAC 用 cluster-admin**：測試環境全開。正式環境應降級為自訂 Role。

3. **port-forward 持久性**：port-forward 斷線即失效。
   可考慮用 systemd unit 或 tmux 保持常駐，或改用 NodePort/LoadBalancer。

## 產出檔案

| 檔案 | 用途 |
|------|------|
| `k8s-manifests/mcp-system/values-woowtech.yaml` | Helm values |
| `k8s-manifests/mcp-system/config.toml` | MCP Server 設定（若需獨立掛載）|
