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

      // Reply from a macOS notification: open that notification's chat (as clicking it
      // would), check the open chat's name matches, then type and send. If anything
      // doesn't match, nothing is sent.
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      const norm = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const textOf = (el) => {
        // Emoji are <img alt="😀"> in WhatsApp Web, so read their alt text too.
        let out = '';
        el.childNodes.forEach((node) => {
          if (node.nodeType === Node.TEXT_NODE) out += node.textContent;
          else if (node.nodeName === 'IMG') out += node.getAttribute('alt') || '';
          else if (node.nodeType === Node.ELEMENT_NODE) out += textOf(node);
        });
        return out;
      };
      const openChatName = () => {
        const el = document.querySelector('#main header [data-testid="conversation-info-header-chat-title"]')
          || document.querySelector('#main header span[dir="auto"]');
        return el ? norm(textOf(el)) : '';
      };
      const composer = () => document.querySelector('#main footer div[contenteditable="true"]');
      const sendButton = () => {
        const icon = document.querySelector('#main footer [data-icon="send"], #main footer [data-icon="wds-ic-send-filled"]');
        return (icon && (icon.closest('button') || icon)) || document.querySelector('#main footer button[aria-label="Send"]');
      };

      window.__sumiReply = async (id, title, text) => {
        const n = live.get(String(id));
        const want = norm(title);
        if (!n) return 'expired';
        if (!want || !String(text).trim()) return 'invalid';

        n._fire('click');
        for (let i = 0; i < 40 && !(openChatName() === want && composer()); i++) await sleep(100);
        const box = composer();
        if (!box || openChatName() !== want) return 'wrong-chat';

        box.focus();
        document.execCommand('insertText', false, text);
        await sleep(150);
        if (!norm(box.textContent).includes(norm(text).slice(0, 20))) return 'not-typed';

        const button = sendButton();
        if (button) button.click();
        else box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));

        for (let i = 0; i < 20 && norm(box.textContent); i++) await sleep(100);
        return norm(box.textContent) ? 'not-sent' : 'sent';
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
