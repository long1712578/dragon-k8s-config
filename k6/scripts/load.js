// ─────────────────────────────────────────────────────────────
// K6 Load Test — api-gateway
// Mục đích: Kiểm tra hiệu năng dưới tải thực tế
//
// Stages:
//   0→10 VU trong 1 phút  (ramp up)
//   10 VU trong 3 phút    (sustained load)
//   10→0 VU trong 1 phút  (ramp down)
//
// Chạy: k6 run load.js -e BASE_URL=http://stg.api.dragon.local
// ─────────────────────────────────────────────────────────────
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate   = new Rate('errors');
const apiDuration = new Trend('api_duration', true);

export const options = {
  stages: [
    { duration: '1m',  target: 10 },  // ramp up
    { duration: '3m',  target: 10 },  // load
    { duration: '1m',  target: 0  },  // ramp down
  ],
  thresholds: {
    http_req_failed:   ['rate<0.05'],    // < 5% lỗi
    http_req_duration: ['p(95)<3000'],   // 95% < 3s
    http_req_duration: ['p(99)<5000'],   // 99% < 5s
    errors:            ['rate<0.05'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  group('health', () => {
    const res = http.get(`${BASE_URL}/health/ready`);
    const ok = check(res, {
      'status 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
    errorRate.add(!ok);
    apiDuration.add(res.timings.duration);
  });

  // TODO: Thêm các endpoint thực tế của api-gateway vào đây
  // group('list products', () => {
  //   const res = http.get(`${BASE_URL}/api/products`);
  //   ...
  // });

  sleep(1);
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data),
  };
}

// helper — k6 built-in
function textSummary(data, opts) {
  return JSON.stringify(data.metrics, null, 2);
}
