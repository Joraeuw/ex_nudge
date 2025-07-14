export const PWAUtils = {
  isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches;
  },

  isIOSStandalone() {
    return window.navigator.standalone === true;
  },

  isPWAMode() {
    return this.isStandalone() || 
           this.isIOSStandalone() ||
           window.matchMedia('(display-mode: minimal-ui)').matches ||
           window.matchMedia('(display-mode: fullscreen)').matches;
  }
};