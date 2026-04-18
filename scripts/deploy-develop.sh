#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# deploy-develop.sh
# Deploy toàn bộ Dragon stack lên môi trường develop
#
# Cách chạy (trên VPS, từ thư mục dragon-k8s-config):
#   bash scripts/deploy-develop.sh
#
# Yêu cầu:
#   - K3s đã cài sẵn
#   - Secret ghcr-secret đã tạo (xem Docs/VPS-SETUP-GUIDE.md bước 3)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# Màu sắc để log dễ đọc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}▶ $1${NC}"; }
warn()   { echo -e "${YELLOW}⚠ $1${NC}"; }
success(){ echo -e "${GREEN}✅ $1${NC}"; }
error()  { echo -e "${RED}❌ $1${NC}"; exit 1; }

MANIFEST_DIR="deploy/develop"

# ── Kiểm tra kubectl hoạt động ────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  # K3s đặt kubectl tại đây
  if [ -f /usr/local/bin/k3s ]; then
    ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
    log "Linked kubectl → k3s"
  else
    error "kubectl không tìm thấy. K3s đã cài chưa?"
  fi
fi

log "Bắt đầu deploy Dragon develop stack..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── [1/6] Namespace ───────────────────────────────────────────
log "[1/6] Tạo namespace dragon-develop..."
kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
kubectl get ns dragon-develop
echo ""

# ── [2/6] PVC cho SQLite ──────────────────────────────────────
log "[2/6] Tạo PVC cho SQLite database..."
kubectl apply -f "${MANIFEST_DIR}/identity-sqlite-pvc.yaml"

# Chờ PVC bound
echo "  Chờ PVC sẵn sàng..."
for i in {1..30}; do
  STATUS=$(kubectl get pvc identity-sqlite-pvc -n dragon-develop -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "$STATUS" = "Bound" ]; then
    success "PVC đã Bound!"
    break
  fi
  echo -n "."
  sleep 2
done
echo ""

# ── [3/6] Identity Service (SSO) ──────────────────────────────
log "[3/6] Deploy Identity Service (SSO)..."
warn "Lần đầu chạy: .NET 9 + EF migration + seed data → cần 2-3 phút"
kubectl apply -f "${MANIFEST_DIR}/identity-service.yaml"
kubectl rollout status deployment/identity-service -n dragon-develop --timeout=5m
success "Identity Service đang chạy!"
echo ""

# ── [4/6] API Gateway ─────────────────────────────────────────
log "[4/6] Deploy API Gateway (Ocelot)..."
kubectl apply -f "${MANIFEST_DIR}/api-gateway.yaml"
kubectl rollout status deployment/api-gateway -n dragon-develop --timeout=3m
success "API Gateway đang chạy!"
echo ""

# ── [5/6] CV Website ──────────────────────────────────────────
log "[5/6] Deploy CV Website (nginx)..."
kubectl apply -f "${MANIFEST_DIR}/sample-service.yaml"
kubectl rollout status deployment/sample-service -n dragon-develop --timeout=1m
success "CV Website đang chạy!"
echo ""

# ── [6/6] Cloudflare Tunnel (optional) ───────────────────────
if kubectl get secret cloudflare-tunnel-secret -n dragon-develop &>/dev/null; then
  log "[6/6] Deploy Cloudflare Tunnel..."
  kubectl apply -f "${MANIFEST_DIR}/cloudflare-tunnel.yaml"
  kubectl rollout status deployment/cloudflare-tunnel -n dragon-develop --timeout=2m
  success "Cloudflare Tunnel đang chạy!"
else
  warn "[6/6] Bỏ qua Cloudflare Tunnel — chưa có secret 'cloudflare-tunnel-secret'"
  echo "  → Setup tunnel sau theo hướng dẫn: Docs/VPS-SETUP-GUIDE.md bước 7"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Deploy xong! Trạng thái các pods:"
echo ""
kubectl get pods -n dragon-develop
echo ""

# ── Quick health check ────────────────────────────────────────
log "Quick health check..."
echo ""

# Test identity service
if kubectl exec -n dragon-develop deploy/api-gateway -- \
   curl -sf http://identity-service/health/live &>/dev/null; then
  success "Identity Service: Healthy ✅"
else
  warn "Identity Service: Chưa sẵn sàng (có thể đang warm up)"
fi

# Test sample-service
if kubectl exec -n dragon-develop deploy/api-gateway -- \
   curl -sf http://sample-service/healthz &>/dev/null; then
  success "CV Website: Healthy ✅"
else
  warn "CV Website: Chưa sẵn sàng"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Các lệnh hữu dụng:"
echo "  Xem logs SSO:     kubectl logs -f deploy/identity-service -n dragon-develop"
echo "  Xem logs Gateway: kubectl logs -f deploy/api-gateway -n dragon-develop"
echo "  Xem events:       kubectl get events -n dragon-develop --sort-by=.lastTimestamp"
echo ""
echo "📖 Bước tiếp theo: Setup Cloudflare Tunnel → Docs/VPS-SETUP-GUIDE.md bước 7"
