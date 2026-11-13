// MES 앱 설치(전체 화면 실행)용 최소 서비스워커 — 캐시하지 않고 항상 최신 화면을 네트워크에서 받는다
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
