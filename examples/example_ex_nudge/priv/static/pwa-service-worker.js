self.addEventListener('push', event => {
  console.log('Push event received:', event);

  if (!event.data) {
    console.log('Push event but no data');
    return;
  }

  try {
    const data = event.data.json();
    
    const options = {
      body: data.body,
      icon: data.icon || '/images/logo.png',
      badge: data.badge || '/images/logo.png',
      image: data.image || '/images/logo.png',
      data: {...data.data, defaultUrl: '/'},
      tag: data.tag || 'default',
      requireInteraction: true,
      actions: data.actions || [],
      silent: false,
      renotify: true,
      timestamp: Date.now()
    };

    event.waitUntil(
      self.registration.showNotification(data.title, options)
        .then(() => {
          return self.clients.matchAll();
        })
        .then(clients => {
          clients.forEach(client => {
            client.postMessage({
              type: 'NOTIFICATION_CREATED',
              title: data.title,
              body: data.body,
              timestamp: Date.now()
            });
          });
          
          return self.registration.getNotifications();
        })
        .then(activeNotifications => {  
          return self.clients.matchAll().then(clients => {
            clients.forEach(client => {
              client.postMessage({
                type: 'NOTIFICATION_STATUS',
                count: activeNotifications.length, 
                message: 'Notification created!'
              });
            });
          });
        })
        .catch(error => {
          return self.clients.matchAll().then(clients => {
            clients.forEach(client => {
              client.postMessage({
                type: 'NOTIFICATION_ERROR',
                error: error.message
              });
            });
          });
        })
    );

  } catch (error) {
    console.error('Error processing push:', error);
  }
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
    
  event.waitUntil(
    clients.openWindow(`/`)
  );
});