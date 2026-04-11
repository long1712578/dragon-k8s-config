# Dragon K8s GitOps

Repo này chứa Kubernetes manifests cho tất cả services trong hệ thống Dragon. Được cập nhật tự động bởi CI/CD workflows khi push tag hoặc push lên branch `develop`.

---

## Kiến trúc tổng quan

```
Internet → Traefik Ingress → api-gateway → identity-service
                                         → sample-service
```

| Service | Image | Port | Health |
|---|---|---|---|
| api-gateway | `ghcr.io/longpham1712578/dragon-api-gateway` | 8080 | `/health/live`, `/health/ready` |
| identity-service | `ghcr.io/longpham1712578/identity-service` | 8080 | `/health/live`, `/health/ready` |
| sample-service | `ghcr.io/longpham1712578/sample-service` | 80 | `/healthz` |

---

## Environments & Namespaces

| Environment | Namespace | Trigger |
|---|---|---|
| develop | `dragon-develop` | push to branch `develop` |
| staging | `dragon-staging` | push tag `qc_v*` (ví dụ `qc_v1.2.0`) |
| production | `dragon-production` | push tag `v[0-9]*` (ví dụ `v1.2.0`) |

---

## Tag strategy

| Env | Format ví dụ |
|---|---|
| develop | `develop-a1b2c3d4` (short SHA) |
| staging | `staging-qc_v1.2.0` |
| production | `production-v1.2.0` |

---

## Secrets cần thiết

### 1. GitHub Actions Secrets (cấu hình trong từng service repo)

| Secret | Mô tả |
|---|---|
| `GITHUB_TOKEN` | Tự động có sẵn — dùng để push image lên GHCR |
| `GITOPS_TOKEN` | Personal Access Token có quyền `repo` — dùng để clone & push vào repo này |

### 2. Kubernetes Secret cho GHCR pull

Chạy lệnh sau trên mỗi cluster cho cả 3 namespace:

```bash
# Thay YOUR_GITHUB_USERNAME và YOUR_PAT
for NS in dragon-develop dragon-staging dragon-production; do
  kubectl create secret docker-registry ghcr-secret \
    --docker-server=ghcr.io \
    --docker-username=YOUR_GITHUB_USERNAME \
    --docker-password=YOUR_PAT \
    --namespace="${NS}"
done
```

### 3. Kubernetes Secret cho IdentityService database

```bash
for NS in dragon-develop dragon-staging dragon-production; do
  kubectl create secret generic identity-service-secrets \
    --from-literal=ConnectionStrings__Default="Server=...;Database=IdentityDb;..." \
    --namespace="${NS}"
done
```

---

## Cấu trúc thư mục

```
deploy/
  develop/
    namespace.yaml
    api-gateway.yaml
    identity-service.yaml
    sample-service.yaml
  staging/   (cùng cấu trúc)
  production/ (cùng cấu trúc, replicas: 2)
gitops-templates/  # template chung để tạo manifest mới
k6/                # load test scripts
scripts/           # runner setup
```

---

## Quy trình deploy

### Deploy develop
```bash
# Trên service repo
git checkout develop
git push origin develop
# → CI tự động build & push image rồi cập nhật deploy/develop/*.yaml
```

### Deploy staging
```bash
git tag qc_v1.2.0
git push origin qc_v1.2.0
```

### Deploy production
```bash
git tag v1.2.0
git push origin v1.2.0
```

---

## Rollback

```bash
# Xem lịch sử commit của manifest
git log --oneline deploy/production/api-gateway.yaml

# Khôi phục về commit cụ thể
git checkout <commit-hash> -- deploy/production/api-gateway.yaml
git commit -m "rollback(production): api-gateway to <commit-hash>"
git push

# ArgoCD/FluxCD sẽ tự detect diff và re-apply
# Hoặc apply thủ công:
kubectl apply -f deploy/production/api-gateway.yaml
```

---

## Runner management

```bash
# Kiểm tra trạng thái
systemctl status actions.runner.*.service

# Khởi động lại
systemctl restart actions.runner.*.service

# Hoặc nếu dùng script
cd /opt/github-runner && ./svc.sh start
```

---

*Author: Long Pham*