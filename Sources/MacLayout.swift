import AppKit

/// "Mac Layout" (View menu): a native sidebar in place of WhatsApp Web's icon strip, the
/// page edge to edge under the title bar, and the Mac system font in the page.
///
/// The sidebar mirrors WhatsApp's own navigation buttons (`button[data-navbar-item]`), so it
/// shows whatever tabs WhatsApp has, and clicking a row clicks the matching button. If
/// WhatsApp changes those buttons and none are found, the sidebar hides itself and the page
/// keeps its own strip.
enum MacLayout {
    private static let key = "MacLayout"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Reports the navigation buttons to the app (message "nav") and hides WhatsApp's strip
    /// while the native sidebar shows them.
    static func pageScript(on: Bool) -> String {
        let css = (try? JSONEncoder().encode(Self.css)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (() => {
          if (window.__sumiNav) { window.__sumiNav.setLayout(\(on)); return; }
          const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nav;
          if (!bridge) return;
          const css = \(css);
          let macLayout = \(on);
          let rail = null;
          let last = '';
          const root = document.documentElement;
          root.classList.toggle('sumi-mac', macLayout);

          const putStyle = () => {
            let style = document.getElementById('sumi-layout');
            if (!style) { style = document.createElement('style'); style.id = 'sumi-layout'; }
            style.textContent = css;
            (document.head || root).appendChild(style);
          };
          putStyle();
          document.addEventListener('DOMContentLoaded', putStyle);

          const buttons = () => Array.from(document.querySelectorAll('button[data-navbar-item]'));
          const ancestorOf = (nodes) => {
            let node = nodes[0];
            while (node && !nodes.every((n) => node.contains(n))) node = node.parentElement;
            return node;
          };

          // Throttled rescan whenever the strip changes (selection, unread counts).
          let pending = false;
          const soon = () => {
            if (pending) return;
            pending = true;
            setTimeout(() => { pending = false; scan(); }, 120);
          };
          const observer = new MutationObserver(soon);

          // The strip: the column holding all the buttons, without the chat list or chat.
          const content = '#side, #pane-side, #main';
          const findRail = (list) => {
            if (rail && rail.isConnected && list.every((b) => rail.contains(b))) return rail;
            let node = ancestorOf(list);
            if (!node) return null;
            const header = node.closest('header');
            if (header && !header.querySelector(content)) {
              node = header;
            } else {
              while (node.parentElement && node.parentElement !== document.body) {
                const parent = node.parentElement;
                const width = parent.getBoundingClientRect().width;
                if (width === 0 || width > 140 || parent.querySelector(content)) break;
                node = parent;
              }
            }
            // Never hide anything that holds the chats, or wider than an icon strip.
            if (node.querySelector(content) || node.getBoundingClientRect().width > 160) return null;
            if (rail && rail !== node) rail.removeAttribute('data-sumi-rail');
            rail = node;
            rail.setAttribute('data-sumi-rail', '');
            observer.disconnect();
            observer.observe(rail, { subtree: true, childList: true, characterData: true, attributes: true,
                                     attributeFilter: ['aria-pressed', 'data-navbar-item-selected', 'src'] });
            return rail;
          };

          // Unread count: digits in the button's own text, not in its icon.
          const badgeOf = (button) => {
            const text = Array.from(button.querySelectorAll('span, div'))
              .filter((n) => n.children.length === 0 && !n.closest('svg'))
              .map((n) => n.textContent).join(' ');
            const match = text.match(/\\d+\\+?/);
            return match ? match[0] : '';
          };

          // WhatsApp leaves room for the strip in the layers next to it (the drawer, the column
          // dividers) with a fixed offset. Those offsets are marked so the CSS can zero them
          // while the strip is hidden.
          const unshift = () => {
            if (!rail || !rail.parentElement) return;
            // The strip's CSS width still reads while it's hidden ("64px").
            const width = getComputedStyle(rail).width;
            if (!/^[1-9]\\d*(\\.\\d+)?px$/.test(width)) return;
            const layers = [];
            for (const sibling of rail.parentElement.children) {
              if (sibling !== rail) layers.push(sibling, ...sibling.children);
            }
            for (const el of layers) {
              if (el.hasAttribute('data-sumi-shift')) continue;
              const style = getComputedStyle(el);
              const kinds = [];
              if (/absolute|fixed/.test(style.position) && style.insetInlineStart === width) kinds.push('inset');
              if (style.marginInlineStart === width) kinds.push('margin');
              if (kinds.length) el.setAttribute('data-sumi-shift', kinds.join(' '));
            }
          };

          // The page's colours along its top edge, for the strip above the page: the chat list
          // side, the other side, and where they meet.
          // A see-through colour (the glassy chat header) is blended over what's behind it.
          // "rgb(255, 255, 255)", "rgba(…, 0.5)" or "color(srgb 1 1 1 / 0.74)" (0–1 channels).
          const rgba = (color) => {
            const m = color.match(/[\\d.]+/g);
            if (!m || m.length < 3) return null;
            const scale = /^color\\(/.test(color) ? 255 : 1;
            return [m[0] * scale, m[1] * scale, m[2] * scale, m.length > 3 ? +m[3] : 1];
          };
          const colorAt = (node) => {
            let layers = [];
            while (node && node !== root) {
              const c = rgba(getComputedStyle(node).backgroundColor || '');
              if (c && c[3] > 0) {
                layers.push(c);
                if (c[3] >= 1) break;
              }
              node = node.parentElement;
            }
            if (!layers.length) return '';
            let [r, g, b] = layers[layers.length - 1][3] >= 1 ? layers.pop() : [255, 255, 255];
            for (const [lr, lg, lb, la] of layers.reverse()) {
              r = lr * la + r * (1 - la); g = lg * la + g * (1 - la); b = lb * la + b * (1 - la);
            }
            return 'rgb(' + Math.round(r) + ', ' + Math.round(g) + ', ' + Math.round(b) + ')';
          };

          // Soft shadows, as in the Mac app: the search field, the round buttons above the
          // chat list, and the message box. Each is found by shape (a rounded box around the
          // field), so a WhatsApp change just leaves them flat.
          const mark = (el, kind) => {
            if (el && el.getAttribute('data-sumi-float') !== kind) el.setAttribute('data-sumi-float', kind);
          };
          const roundedAround = (el, stop) => {
            for (let n = el; n && n !== stop; n = n.parentElement) {
              if (parseFloat(getComputedStyle(n).borderTopLeftRadius) >= 12) return n;
            }
            return null;
          };
          const float = () => {
            const side = document.querySelector('#side');
            if (side) {
              const search = side.querySelector('input[type="text"], input:not([type]), [role="textbox"]');
              if (search) mark(roundedAround(search, side), 'field');
              const top = side.getBoundingClientRect().top;
              for (const button of (side.parentElement || side).querySelectorAll('button')) {
                if (button.hasAttribute('data-sumi-float')) continue;
                const box = button.getBoundingClientRect();
                const style = getComputedStyle(button);
                if (box.bottom <= top + 4 && box.width >= 32 && box.width <= 48 && Math.abs(box.width - box.height) < 2
                    && parseFloat(style.borderTopLeftRadius) >= 16) {
                  mark(button, (rgba(style.backgroundColor) || [0, 0, 0, 0])[3] === 0 ? 'plain' : 'button');
                }
              }
            }
            const footer = document.querySelector('#main footer');
            const composer = footer && footer.querySelector('[contenteditable="true"]');
            if (composer) mark(roundedAround(composer, footer), 'field');
          };
          const topEdge = () => {
            const side = document.querySelector('#side');
            const left = colorAt(document.elementFromPoint(4, 4)) || colorAt(side || document.querySelector('#app'));
            if (!side) return { background: left, backgroundRight: '', split: 0 };
            const box = side.getBoundingClientRect();
            return {
              background: left,
              backgroundRight: colorAt(document.elementFromPoint(window.innerWidth - 4, 4)),
              split: Math.round(box.left < window.innerWidth / 2 ? box.right : box.left),
            };
          };

          const scan = () => {
            const list = buttons();
            const usable = list.length >= 2 && !!findRail(list);
            let items = [];
            if (usable) {
              // WhatsApp groups the main tabs apart from Settings and Profile.
              const top = ancestorOf(list);
              const sections = list.map((b) => {
                let n = b;
                while (n.parentElement && n.parentElement !== top) n = n.parentElement;
                return n;
              });
              const distinct = Array.from(new Set(sections));
              const split = distinct.length >= 2 && distinct.length < list.length;
              items = list.map((b, index) => {
                const img = b.querySelector('img');
                const icon = b.querySelector('[data-icon]');
                const label = b.getAttribute('aria-label') || b.getAttribute('title') || '';
                const avatar = img && /^https?:/.test(img.src) ? img.src : '';
                return {
                  index, label, avatar,
                  icon: icon ? icon.getAttribute('data-icon') : '',
                  selected: b.getAttribute('aria-pressed') === 'true'
                    || b.getAttribute('data-navbar-item-selected') === 'true',
                  badge: badgeOf(b),
                  bottom: split ? distinct.indexOf(sections[index]) > 0 : (!!img || /settings|profile/i.test(label)),
                };
              });
            }
            if (usable) unshift();
            if (macLayout) float();
            root.classList.toggle('sumi-nav-hidden', macLayout && usable);
            const message = JSON.stringify({ items, ...topEdge() });
            if (message !== last) { last = message; bridge.postMessage(message); }
          };

          window.__sumiNav = {
            click(index, label) {
              const list = buttons();
              const button = list.find((b) => b.getAttribute('aria-label') === label) || list[index];
              if (!button) return;
              button.click();
              setTimeout(scan, 60);
              setTimeout(scan, 400);
            },
            setLayout(on) {
              macLayout = on;
              root.classList.toggle('sumi-mac', on);
              last = '';
              scan();
            },
          };
          setInterval(scan, 1000);
          scan();
        })();
        """
    }

    /// Only active while the page has the `sumi-mac` class (Mac Layout on).
    private static let css = """
    html.sumi-nav-hidden [data-sumi-rail] { display: none !important; }
    html.sumi-nav-hidden [data-sumi-shift~="inset"] { inset-inline-start: 0 !important; }
    html.sumi-nav-hidden [data-sumi-shift~="margin"] { margin-inline-start: 0 !important; }
    html.sumi-mac {
      --sumi-font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", "Apple Color Emoji", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    html.sumi-mac body, html.sumi-mac body *:not(svg):not(svg *):not(code):not(pre) { font-family: var(--sumi-font) !important; }
    html.sumi-mac [data-sumi-float] { box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.05), 0 2px 10px rgba(0, 0, 0, 0.08) !important; }
    html.sumi-mac [data-sumi-float="plain"], html.sumi-mac #side [data-sumi-float="field"] {
      background-color: var(--WDS-surface-default, #fff) !important;
    }
    html.sumi-mac #main > header {
      background-color: color-mix(in srgb, var(--WDS-surface-default, #fff) 74%, transparent) !important;
      -webkit-backdrop-filter: blur(20px) saturate(1.6);
      backdrop-filter: blur(20px) saturate(1.6);
    }
    html.sumi-mac ::-webkit-scrollbar { width: 8px !important; height: 8px !important; }
    html.sumi-mac ::-webkit-scrollbar-thumb { border-radius: 8px; }
    """
}

extension NSColor {
    /// "#RRGGBB", "#RGB", "rgb(r, g, b)" or "rgba(r, g, b, a)"; nil for anything else or fully clear.
    convenience init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespaces).lowercased()
        var parts: [Double] = []
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            parts = [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF), 1]
        } else if text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") {
            parts = text[text.index(after: open)..<close]
                .split(whereSeparator: { ", /".contains($0) })
                .compactMap { Double($0) }
            if parts.count == 3 { parts.append(1) }
        }
        guard parts.count == 4, parts[3] > 0 else { return nil }
        self.init(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts[3])
    }
}
