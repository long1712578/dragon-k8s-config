#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD Bootstrap Script — Dragon Develop Environment
#
# Chạy script này MỘT LẦN từ máy local (đã có kubeconfig của K3s).
# Sau khi chạy xong, ArgoCD sẽ tự động quản lý mọi deployment.
#
# Prerequisites:
#   - kubectl đã kết nối với K3s cluster
#   - Có GitHub Personal Access Token (classic) với scope: read:packages
#
# Usage:
#   GHCR_PAT=<your_token> ./scripts/argocd-bootstrap.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GHCR_USER="long1712578"
GHCR_PAT="${GHCR_PAT:?'Set GHCR_PAT env var: export GHCR_PAT=your_github_pat'}"
ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="dragon-develop"
ARGOCD_VERSION="stable"  # hoặc pin cụ thể: v2.12.x

echo "═══════════════════════════════════════════════════════"
echo "  Dragon DevOps — ArgoCD Bootstrap"
echo "═══════════════════════════════════════════════════════"

# ── 1. Cài ArgoCD (lightweight: không có Dex SSO, không HA) ──────────────────
echo ""
echo "▶ [1/5] Installing ArgoCD..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply --server-side --force-conflicts \
  -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Tắt Dex (SSO) để tiết kiệm ~100MB RAM — chỉ dùng local admin account
echo "▶ Disabling Dex (SSO) to save RAM..."
kubectl delete deployment argocd-dex-server -n "${ARGOCD_NAMESPACE}" --ignore-not-found=true

# Giảm replica argocd-server (dev environment, không cần HA)
kubectl scale deployment argocd-server --replicas=1 -n "${ARGOCD_NAMESPACE}"

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=180s
kubectl rollout status deployment/argocd-repo-server -n "${ARGOCD_NAMESPACE}" --timeout=180s
kubectl rollout status deployment/argocd-application-controller -n "${ARGOCD_NAMESPACE}" --timeout=180s

echo "✅ ArgoCD installed!"

# ── 2. Tạo GHCR pull secret cho dragon-develop namespace ─────────────────────
echo ""
echo "▶ [2/5] Creating GHCR pull secret in ${APP_NAMESPACE}..."
kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_PAT}" \
  --namespace="${APP_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ GHCR pull secret created!"

# ── 3. Apply ArgoCD Application manifest ─────────────────────────────────────
echo ""
echo "▶ [3/5] Applying ArgoCD Application (dragon-develop)..."
kubectl apply -f "$(dirname "$0")/../apps/dragon-develop.yaml"
echo "✅ ArgoCD Application created!"

# ── 4. Lấy mật khẩu ArgoCD admin ─────────────────────────────────────────────
echo ""
echo "▶ [4/5] Fetching ArgoCD admin password..."
echo "⏳ Waiting for initial-admin-secret..."
kubectl wait secret/argocd-initial-admin-secret \
  -n "${ARGOCD_NAMESPACE}" \
  --for=jsonpath='{.data.password}' \
  --timeout=60s 2>/dev/null || true

ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(secret not ready yet)")

# ── 5. Hướng dẫn truy cập ────────────────────────────────────────────────────
echo ""
echo "▶ [5/5] Access instructions..."
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Bootstrap Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  ArgoCD Dashboard:"
echo "    Option A (Cloudflare Tunnel):"
echo "      Add to cloudflare-tunnel.yaml:"
echo "      - hostname: argo.longdev.store"
echo "        service: https://argocd-server.argocd.svc.cluster.local:443"
echo "        originRequest:"
echo "          noTLSVerify: true"
echo ""
echo "    Option B (Port-forward, local only):"
echo "      kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "      Open: https://localhost:8080"
echo ""
echo "  Credentials:"
echo "    Username: admin"
echo "    Password: ${ARGOCD_PASSWORD}"
echo ""
echo "  ⚠️  Change password after first login:"
echo "    argocd login localhost:8080 --insecure"
echo "    argocd account update-password"
echo ""
echo "  Next: ArgoCD will auto-sync deploy/develop/ within ~3 minutes"
echo "  Check sync status:"
echo "    kubectl get applications -n argocd"
echo "═══════════════════════════════════════════════════════"
