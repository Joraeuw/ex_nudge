import { PWAUtils } from "./pwa-utils";

export default {
  mounted() {
    console.log('Push notification hook mounted');
    this.vapidPublicKey = document.getElementById('vapid-public-key').value;
    this.swRegistration = null;
    this.subscribeBtn = document.getElementById('subscribe-btn');
    this.init();
  },

  async init() {
    if (!('serviceWorker' in navigator)) {
      console.log('Service Worker not supported');
      return;
    }

    try {
      this.swRegistration = await navigator.serviceWorker.register('/pwa-service-worker.js');
      await navigator.serviceWorker.ready;
      console.log('Service Worker ready');

      this.updateStatus();
      this.setupEventListeners();

      window.addEventListener("phx:device_removed", e => {
        e.preventDefault();
        this.handleDeviceRemoved(e.detail.endpoint);
      })


      const installBtn = document.getElementById('install-button');
      
      if(installBtn && PWAUtils.isPWAMode()) {
          this.pushEvent('is-pwa', true);
      }

    } catch (error) {
      console.error('Push hook init failed:', error);
    }
  },

  setupEventListeners() {
    if (this.subscribeBtn) {
      this.subscribeBtn.addEventListener('click', async () => {
        const isSubscribed = await this.isSubscribed();
        if (isSubscribed) {
          await this.unsubscribe();
        } else {
          await this.subscribe();
        }
        this.updateStatus();
      });
    }
  },

  async isSubscribed() {
    if (!this.swRegistration) return false;
    const subscription = await this.swRegistration.pushManager.getSubscription();
    return !!subscription;
  },

  async subscribe() {
    try {
      console.log('Starting subscription process...');
      const permission = await Notification.requestPermission();
      console.log('Permission result:', permission);
      if (permission !== 'granted') {
        throw new Error('Permission denied');
      }
      
      const subscription = await this.swRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.vapidPublicKey)
      });
      console.log('Subscription created:', subscription);
      this.pushEvent('subscribe', {
        subscription: subscription.toJSON()
      });
    } catch (error) {
      console.error('Subscribe failed:', error);
    }
  },

  async unsubscribe() {
    try {
      const subscription = await this.swRegistration.pushManager.getSubscription();
      if (subscription) {
        await subscription.unsubscribe();
        this.pushEvent('unsubscribe', { endpoint: subscription.endpoint });
        console.log('Unsubscribed from push notifications');
      }
    } catch (error) {
      console.error('Unsubscribe failed:', error);
    }
  },

  async updateStatus() {
    if (!this.swRegistration) return;
    try {
      const subscription = await this.swRegistration.pushManager.getSubscription();
      if (this.subscribeBtn) {
        if (subscription) {
          this.subscribeBtn.textContent = 'Disable Notifications';
          this.subscribeBtn.classList.remove('bg-gradient-to-r', 'from-green-400', 'to-green-500', 'hover:from-green-500', 'hover:to-green-600');
          this.subscribeBtn.classList.add('bg-gradient-to-r', 'from-red-400', 'to-red-500', 'hover:from-red-500', 'hover:to-red-600');
        } else {
          this.subscribeBtn.textContent = 'Enable Notifications';
          this.subscribeBtn.classList.remove('bg-gradient-to-r', 'from-red-400', 'to-red-500','hover:from-red-500', 'hover:to-red-600');
          this.subscribeBtn.classList.add('bg-gradient-to-r', 'from-green-400', 'to-green-500','hover:from-green-500', 'hover:to-green-600');
        }
      }
      const indicator = document.getElementById('status-indicator');
      if (indicator) {
        indicator.className = subscription ?
          'w-3 h-3 rounded-full bg-green-500' :
          'w-3 h-3 rounded-full bg-gray-400';
      }
    } catch (error) {
      console.error('Error updating status:', error);
    }
  },

  async handleDeviceRemoved(removedEndpoint) {
    if (!this.swRegistration) return;
    
    try {
      const currentSubscription = await this.swRegistration.pushManager.getSubscription();
      
      if (currentSubscription && currentSubscription.endpoint === removedEndpoint) {
        await currentSubscription.unsubscribe();
        await this.updateStatus();
      }
    } catch (error) {
      console.error('Error handling device removal:', error);
    }
  },

  urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding)
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    const rawData = window.atob(base64);
    return new Uint8Array([...rawData].map(char => char.charCodeAt(0)));
  },

  updated() {
    this.updateStatus();
  }
};
