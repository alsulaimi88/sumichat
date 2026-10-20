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

      // Chat translation: while on, every message in the open chat is sent to the app
      // (by its text) and the translation is shown under it. Translations are kept by
      // text, so messages WhatsApp redraws get theirs back without asking again.
      const translations = new Map(); // text -> translation, or null if none is needed
      const pending = new Set();
      let translating = false;
      let observer = null;
      let scanTimer = null;

      const messageNodes = () => document.querySelectorAll('#main div.copyable-text[data-pre-plain-text]');
      const messageText = (node) => {
        const el = node.querySelector('span.selectable-text');
        return el ? textOf(el).trim() : '';
      };
      const showTranslation = (node, translation) => {
        let div = node.querySelector(':scope > .sumi-translation');
        if (!translation) { if (div) div.remove(); return; }
        const missing = typeof translation === 'object' ? translation.missing : null;
        if (!div) {
          div = document.createElement('div');
          div.className = 'sumi-translation';
          div.dir = 'auto';
          div.style.cssText = 'margin-top:4px;padding-top:4px;border-top:1px solid rgba(127,127,127,.3);'
            + 'font-style:italic;opacity:.85;white-space:pre-wrap;';
          node.appendChild(div);
        }
        div.textContent = missing
          ? '🌐 ' + missing + " isn't downloaded yet. Translate ▸ Download " + missing + '…'
          : '🌐 ' + translation;
        div.style.fontSize = missing ? '12px' : '';
      };
      const scan = () => {
        if (!translating) return;
        const ask = [];
        messageNodes().forEach((node) => {
          const text = messageText(node);
          if (!text) return;
          if (translations.has(text)) showTranslation(node, translations.get(text));
          else if (!pending.has(text)) { pending.add(text); ask.push(text); }
        });
        const bridge = window.webkit.messageHandlers.translate;
        if (ask.length && bridge) bridge.postMessage({ texts: ask });
      };

      window.__sumiSetChatTranslation = (on) => {
        translating = !!on;
        if (translating) {
          observer = observer || new MutationObserver(() => {
            clearTimeout(scanTimer);
            scanTimer = setTimeout(scan, 400);
          });
          observer.observe(document.body, { childList: true, subtree: true });
          scan();
        } else {
          if (observer) observer.disconnect();
          document.querySelectorAll('.sumi-translation').forEach((n) => n.remove());
        }
      };
      window.__sumiShowTranslations = (items) => {
        items.forEach(({ text, translation, missing }) => {
          pending.delete(text);
          translations.set(text, missing ? { missing } : (translation || null));
        });
        if (translating) scan();
      };
      window.__sumiResetTranslations = () => {
        translations.clear();
        pending.clear();
        document.querySelectorAll('.sumi-translation').forEach((n) => n.remove());
        if (translating) scan();
      };

      // Translating your own message: read and replace what's in the message box, and
      // read the other person's recent messages to tell which language they write in.
      window.__sumiComposerText = () => {
        const box = composer();
        return box ? box.innerText.trim() : null;
      };
      // A 🌐 "Translate my message" button in the typing bar, right after WhatsApp's + button.
      // WhatsApp redraws the bar often, so it's put back whenever it goes missing. If the +
      // button can't be found, there's simply no button (the menu and ⌘⇧M still work).
      const attachButton = () => {
        const icon = document.querySelector('#main footer [data-icon="plus-rounded"], #main footer [data-icon="plus"],'
          + ' #main footer [data-icon="attach-menu-plus"], #main footer [data-icon="clip"]');
        if (icon) return icon.closest('button') || icon.closest('[role="button"]') || icon.parentElement;
        return document.querySelector('#main footer button[aria-label="Attach"], #main footer [title="Attach"]');
      };
      const addTranslateButton = () => {
        const bridge = window.webkit.messageHandlers.translateMine;
        if (!bridge || document.getElementById('sumi-translate-button')) return;
        const attach = attachButton();
        const footer = document.querySelector('#main footer');
        if (!attach || !footer) return;

        // Step out to the item that sits in the bar's row, so the button lines up beside it.
        let slot = attach;
        while (slot.parentElement && slot.parentElement !== footer) {
          const parent = slot.parentElement;
          if (parent.children.length > 1 && getComputedStyle(parent).display.includes('flex')) break;
          slot = parent;
        }

        const button = document.createElement('button');
        button.id = 'sumi-translate-button';
        button.type = 'button';
        button.title = 'Translate my message (⌘⇧M)';
        button.setAttribute('aria-label', 'Translate my message');
        button.style.cssText = 'display:flex;align-items:center;justify-content:center;flex:none;'
          + 'width:40px;height:40px;padding:0;border:0;border-radius:50%;background:transparent;cursor:pointer;'
          + 'color:' + getComputedStyle(attach).color + ';';
        button.innerHTML = '<svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor"'
          + ' stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/>'
          + '<path d="M3 12h18"/><path d="M12 3c2.5 2.5 3.8 5.5 3.8 9s-1.3 6.5-3.8 9c-2.5-2.5-3.8-5.5-3.8-9S9.5 5.5 12 3z"/></svg>';
        button.addEventListener('mouseenter', () => { button.style.background = 'rgba(127,127,127,.15)'; });
        button.addEventListener('mouseleave', () => { button.style.background = 'transparent'; });
        button.addEventListener('mousedown', (e) => e.preventDefault()); // keep the cursor in the message box
        button.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          bridge.postMessage({});
        });
        slot.insertAdjacentElement('afterend', button);
      };
      if (window.webkit.messageHandlers.translateMine) {
        let buttonTimer = null;
        new MutationObserver(() => {
          clearTimeout(buttonTimer);
          buttonTimer = setTimeout(addTranslateButton, 300);
        }).observe(document.documentElement, { childList: true, subtree: true });
      }

      window.__sumiRecentMessages = () => Array.from(messageNodes()).slice(-15).map(messageText).filter(Boolean);
      window.__sumiReplaceComposer = async (text) => {
        const box = composer();
        if (!box) return false;
        box.focus();
        document.execCommand('selectAll', false);
        document.execCommand('insertText', false, text);
        // WhatsApp's editor updates the box a moment later; wait for it before checking.
        const want = norm(text).replace(/[\u200b-\u200d\ufeff]/g, '').slice(0, 30);
        for (let i = 0; i < 15; i++) {
          await sleep(100);
          if (norm(box.innerText).replace(/[\u200b-\u200d\ufeff]/g, '').includes(want)) return true;
        }
        return false;
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
