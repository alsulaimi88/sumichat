/// WKWebView has no web notifications, so WhatsApp would never show any.
/// This replaces `window.Notification` with a version that hands each
/// notification to the app, which shows it in macOS Notification Center.
enum NotificationShim {
    static let source = #"""
    (() => {
      if (window.__sumiShimInstalled) return;
      window.__sumiShimInstalled = true;
      const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.notify;
      if (!bridge) return;

      const live = new Map();
      let nextId = 1;

      class NativeNotification extends EventTarget {
        constructor(title, options = {}) {
          super();
          this.title = String(title ?? '');
          this.body = String(options.body ?? '');
          this.tag = String(options.tag ?? '');
          this.icon = options.icon ?? '';
          this.data = options.data ?? null;
          this.silent = !!options.silent;
          this.onclick = null;
          this.onclose = null;
          this.onshow = null;
          this.onerror = null;
          this._id = String(nextId++);
          live.set(this._id, this);
          if (live.size > 200) live.delete(live.keys().next().value);
          bridge.postMessage({ id: this._id, title: this.title, body: this.body, tag: this.tag, silent: this.silent });
          setTimeout(() => this._fire('show'), 0);
        }
        _fire(type) {
          const event = new Event(type);
          const handler = this['on' + type];
          if (typeof handler === 'function') handler.call(this, event);
          this.dispatchEvent(event);
        }
        close() {
          if (live.delete(this._id)) this._fire('close');
        }
        static get permission() { return 'granted'; }
        static requestPermission(callback) {
          if (typeof callback === 'function') callback('granted');
          return Promise.resolve('granted');
        }
        static get maxActions() { return 0; }
      }

      window.__sumiNotificationClick = (id) => {
        const n = live.get(String(id));
        if (n) n._fire('click');
      };

      Object.defineProperty(window, 'Notification', { value: NativeNotification, writable: true, configurable: true });

      if (navigator.permissions && navigator.permissions.query) {
        const query = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = (desc) => (desc && desc.name === 'notifications')
          ? Promise.resolve({ name: 'notifications', state: 'granted', onchange: null,
                              addEventListener() {}, removeEventListener() {} })
          : query(desc);
      }

      if (window.ServiceWorkerRegistration) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          new NativeNotification(title, options);
          return Promise.resolve();
        };
      }
    })();
    """#
}
