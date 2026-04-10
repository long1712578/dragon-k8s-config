// ─────────────────────────────────────────────────────────────
// K6 Smoke Test — api-gateway
// Mục đích: Kiểm tra service còn sống sau deploy
//   1 VU, 30s, tất cả request phải pass
// Chạy: k6 run smoke.js -e BASE_URL=http://dev.api.dragon.local
// ─────────────────────────────────────────────────────────────
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    http_req_failed:   ['rate<0.01'],   // < 1% lỗi
    http_req_duration: ['p(95)<2000'],  // 95% request < 2s
    errors:            ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  // Health check
  const healthRes = http.get(`${BASE_URL}/health/live`);
  const healthOk = check(healthRes, {
    'health/live returns 200': (r) => r.status === 200,
  });
  errorRate.add(!healthOk);

  // Readiness check
  const readyRes = http.get(`${BASE_URL}/health/ready`);
  const readyOk = check(readyRes, {
    'health/ready returns 200': (r) => r.status === 200,
  });
  errorRate.add(!readyOk);

  sleep(1);
}
