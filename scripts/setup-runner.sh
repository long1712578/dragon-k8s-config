#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Setup GitHub Actions Self-Hosted Runner trên VPS (k3s + Ubuntu 22.04)
#
# Cách chạy trên VPS qua MobaXterm:
#   B1. Trên máy Windows, mở PowerShell:
#         scp scripts/setup-runner.sh root@96.9.228.233:/root/setup-runner.sh
#   B2. SSH vào VPS qua MobaXterm, rồi:
#         chmod +x /root/setup-runner.sh
#         bash /root/setup-runner.sh
#
# Token hết hạn sau 1 giờ — lấy token mới tại:
#   https://github.com/long1712578/dragon-k8s-config/settings/actions/runners/new
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

REPO_URL="https://github.com/long1712578/dragon-k8s-config"
RUNNER_NAME="${RUNNER_NAME:-dragon-runner-1}"
RUNNER_LABELS="develop,staging,production"
RUNNER_DIR="/opt/github-runner"
RUNNER_USER="github-runner"
# Phiên bản khớp với GitHub UI (Settings > Actions > Runners > New runner)
RUNNER_VERSION="2.333.1"
RUNNER_ARCH="linux-x64"

# ── 0. Phải chạy bằng root ────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Script này phải chạy bằng root. Dùng: sudo bash $0"
  exit 1
fi

# ── 1. Nhập registration token ───────────────────────────────
echo ""
echo "┌────────────────────────────────────────────────────┐"
echo "│ Lấy token tại:                                     │"
echo "│ github.com/long1712578/dragon-k8s-config           │"
echo "│ → Settings → Actions → Runners → New self-hosted   │"
echo "└────────────────────────────────────────────────────┘"
echo -n "Dán REGISTRATION TOKEN vào đây (sẽ ẩn): "
read -r -s REG_TOKEN
echo ""
[ -z "${REG_TOKEN}" ] && { echo "❌ Token rỗng!"; exit 1; }

# ── 2. Tạo user chạy runner (không phải root) ───────────────
if ! id "${RUNNER_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${RUNNER_USER}"
  echo "Created user: ${RUNNER_USER}"
fi

# ── 3. Cấp quyền kubectl cho runner user ────────────────────
# k3s lưu kubeconfig tại /etc/rancher/k3s/k3s.yaml
mkdir -p "/home/${RUNNER_USER}/.kube"
cp /etc/rancher/k3s/k3s.yaml "/home/${RUNNER_USER}/.kube/config"
chown -R "${RUNNER_USER}:${RUNNER_USER}" "/home/${RUNNER_USER}/.kube"
chmod 600 "/home/${RUNNER_USER}/.kube/config"

# Thêm symlink kubectl nếu chưa có
if ! command -v kubectl &>/dev/null; then
  ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
  echo "Linked kubectl → k3s"
fi

# ── 4. Download GitHub Actions runner (v2.333.1 khớp GitHub UI) ──
echo "► Downloading runner v${RUNNER_VERSION}..."
mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [ ! -f "actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" ]; then
  curl -fsSL -O "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
fi
echo "► Extracting..."
tar xzf "actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"

# ── 5. Cấu hình runner ────────────────────────────────────────
echo "► Configuring runner..."
sudo -u "${RUNNER_USER}" ./config.sh \
  --url "${REPO_URL}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "_work" \
  --unattended \
  --replace

# ── 6. Cài service systemd ─────────────────────────────────────────
echo "► Installing systemd service..."
./svc.sh install "${RUNNER_USER}"
./svc.sh start

SVC_NAME=$(ls /etc/systemd/system/actions.runner.*.service 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "actions.runner.service")

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ✅ Runner '${RUNNER_NAME}' đã khởi động thành công!          ║"
echo "║     Labels : ${RUNNER_LABELS}              ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Kiểm tra: systemctl status ${SVC_NAME}"
echo "Logs:     journalctl -u ${SVC_NAME} -f"
echo ""
echo "──────────────────────────────────────────────────────"
echo "⚠️  Bước tiếp theo — thêm GitHub Secrets:"
echo "   Settings > Secrets and variables > Actions"
echo ""
echo "   KUBECONFIG_DEVELOP    → chạy lệnh bên dưới để lấy value:"
echo "   cat /etc/rancher/k3s/k3s.yaml | base64 -w0"
echo ""
echo "   KUBECONFIG_STAGING    → cùng giá trị với KUBECONFIG_DEVELOP"
echo "   KUBECONFIG_PRODUCTION → cùng giá trị với KUBECONFIG_DEVELOP"
echo "   GHCR_TOKEN            → PAT mới (quyền read:packages)"
echo "──────────────────────────────────────────────────────"
