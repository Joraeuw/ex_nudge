// ExNudge sends `ExNudge.Notification` structs as JSON whose keys match the
// options of `showNotification`, so the push handler is a simple pass-through.
self.addEventListener('push', event => {
  if (!event.data) {
    console.log('Push event but no data');
    return;
  }

  const payload = event.data.json();

  event.waitUntil(
    self.registration.showNotification(payload.title, payload)
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(clients.openWindow(url));
});

// --- pushsubscriptionchange -------------------------------------------------
//
// When the push service rotates the subscription, the service worker must tell
// the server about the new one. Service workers cannot read the CSRF meta tag,
// so instead the page stored a signed Phoenix.Token (bound to our endpoint) in
// IndexedDB at subscribe time; the server verifies it on the refresh endpoint.

const DB_NAME = 'ex-nudge-example';
const STORE_NAME = 'push-tokens';
const TOKEN_KEY = 'subscription-token';

function openTokenDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE_NAME);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function readToken() {
  const db = await openTokenDb();
  return new Promise((resolve, reject) => {
    const request = db.transaction(STORE_NAME, 'readonly').objectStore(STORE_NAME).get(TOKEN_KEY);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function writeToken(token) {
  const db = await openTokenDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(token, TOKEN_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

self.addEventListener('pushsubscriptionchange', event => {
  event.waitUntil((async () => {
    const token = await readToken();
    if (!token) {
      console.log('pushsubscriptionchange: no stored token, cannot refresh');
      return;
    }

    const applicationServerKey =
      (event.oldSubscription && event.oldSubscription.options.applicationServerKey) || undefined;

    const newSubscription = await self.registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey
    });

    const response = await fetch('/api/push_subscriptions/refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, subscription: newSubscription.toJSON() })
    });

    if (response.ok) {
      const body = await response.json();
      await writeToken(body.token);
    } else {
      console.error('pushsubscriptionchange: refresh rejected', response.status);
    }
  })());
});
