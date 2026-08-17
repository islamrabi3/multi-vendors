// Background push for the web console.
//
// A browser only delivers a push to a *service worker*, and only to one at
// this exact filename — Firebase looks for `/firebase-messaging-sw.js` at the
// site root. Without this file the vendor and admin consoles could ask for
// notification permission and still never receive anything, which is why web
// push was switched off entirely rather than left half-wired.
//
// The config below is the same public web config as `firebase_options.dart`.
// It is not a secret: it identifies the project to Firebase, and every web
// Firebase app ships it in readable JavaScript. A service worker cannot read
// Dart's compile-time defines, so it is repeated here rather than injected.
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyCkrZiXYOaUWQjv3roqdD36Q-AvRwNfw84',
  appId: '1:696253376957:web:235cb92f52c4c0f649cad4',
  messagingSenderId: '696253376957',
  projectId: 'multi-rest-app',
  authDomain: 'multi-rest-app.firebaseapp.com',
  storageBucket: 'multi-rest-app.firebasestorage.app',
});

const messaging = firebase.messaging();

// Fired only when the tab is closed or in the background; a foreground push
// goes to the Dart `onMessage` stream instead, so handling it here as well
// would show every notification twice.
messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const data = payload.data || {};

  self.registration.showNotification(notification.title || 'Kitchen IN', {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Collapses repeats of the same subject — six updates about one order
    // should replace each other rather than stack six deep.
    tag: data.route || data.order_id || 'kitchen-in',
    data,
  });
});

// Bring the console to the front rather than opening a second copy of it, and
// land on whatever the push was about.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = (event.notification.data && event.notification.data.route) || '/';
  const target = new URL('/#' + route, self.location.origin).href;

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if ('focus' in client) {
            if ('navigate' in client) client.navigate(target);
            return client.focus();
          }
        }
        return self.clients.openWindow(target);
      }),
  );
});
