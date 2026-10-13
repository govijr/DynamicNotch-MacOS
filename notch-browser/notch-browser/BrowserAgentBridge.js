(() => {
  if (globalThis.__notchAgent) return;
  let refs = new Map();
  let navigationEpoch = null;
  const documentId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  const failure = (code, message) => ({ ok: false, error: { code, message } });
  const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
  const visible = element => {
    if (!element.isConnected || element.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
  };
  const role = el => {
    if (el.getAttribute('role')) return el.getAttribute('role').split(' ')[0];
    const tag = el.tagName.toLowerCase();
    if (tag === 'a' && el.hasAttribute('href')) return 'link';
    if (tag === 'button' || (tag === 'input' && /^(button|submit|reset|image)$/.test(el.type))) return 'button';
    if (tag === 'input' && el.type === 'checkbox') return 'checkbox';
    if (tag === 'input' && el.type === 'radio') return 'radio';
    if (tag === 'input' && el.type === 'range') return 'slider';
    if (tag === 'select') return el.multiple ? 'listbox' : 'combobox';
    if (tag === 'input' || tag === 'textarea' || el.isContentEditable) return 'textbox';
    if (/^h[1-6]$/.test(tag)) return 'heading';
    if (tag === 'img') return 'image';
    if (tag === 'summary') return 'button';
    return 'element';
  };
  const name = el => {
    const labelled = el.getAttribute('aria-labelledby');
    if (labelled) {
      const root = el.getRootNode();
      const value = labelled.split(/\s+/).map(id => root.getElementById?.(id)?.textContent || '').join(' ');
      if (clean(value)) return clean(value);
    }
    if (el.getAttribute('aria-label')) return clean(el.getAttribute('aria-label'));
    if (el.labels?.length) return clean(Array.from(el.labels).map(label => {
      const copy = label.cloneNode(true);
      copy.querySelectorAll('input,textarea,select,button').forEach(control => control.remove());
      return copy.textContent;
    }).join(' '));
    if (el.tagName === 'IMG') return clean(el.alt);
    if (el.tagName === 'INPUT' && /^(button|submit|reset)$/.test(el.type)) return clean(el.value);
    if (['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) return clean(el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('name'));
    return clean(el.innerText || el.textContent || el.getAttribute('title')).slice(0, 240);
  };
  const fingerprint = el => [el.tagName, el.getAttribute('type') || '', role(el), name(el)].join('|');
  const resolve = ref => {
    const saved = refs.get(String(ref || '').replace(/^@/, ''));
    if (!saved || !saved.element.isConnected || saved.fingerprint !== fingerprint(saved.element)) {
      throw Object.assign(new Error('This reference is outdated. Take a new snapshot and retry.'), { code: 'stale_ref' });
    }
    const el = saved.element;
    if (!visible(el)) throw Object.assign(new Error('The element is hidden. Take a new snapshot.'), { code: 'element_not_visible' });
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') throw Object.assign(new Error('The element is disabled.'), { code: 'element_disabled' });
    return el;
  };
  const events = el => {
    el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
    el.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
  };
  const setValue = (el, value) => {
    if (el.readOnly) throw Object.assign(new Error('The field is read-only.'), { code: 'element_read_only' });
    if (el.isContentEditable) { el.textContent = value; }
    else if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
      if (el instanceof HTMLInputElement && /^(file|checkbox|radio|button|submit|reset|image|hidden)$/.test(el.type)) {
        throw Object.assign(new Error('This input does not support fill.'), { code: 'unsupported_input' });
      }
      const prototype = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(el, value);
    } else throw Object.assign(new Error('Use fill on a textbox or editable element.'), { code: 'wrong_element_type' });
    events(el);
  };
  const candidates = root => {
    const selector = 'a[href],button,input:not([type="hidden"]),textarea,select,summary,[contenteditable="true"],[role],[tabindex],h1,h2,h3,h4,h5,h6,img[alt]';
    const result = Array.from(root.querySelectorAll(selector));
    // Open shadow roots are traversable. Closed roots and iframe documents are
    // reported as limitations rather than guessed at with CSS selectors.
    for (const element of root.querySelectorAll('*')) {
      if (element.shadowRoot) result.push(...candidates(element.shadowRoot));
    }
    return result;
  };
  globalThis.__notchAgent = {
    run(command, args = {}) {
      try {
        // WebKit may restore an old JS world from its back/forward cache.
        // The native epoch still changes, so references cannot survive a trip
        // away from this document and back again.
        if (navigationEpoch !== args.documentEpoch) {
          refs = new Map();
          navigationEpoch = args.documentEpoch;
        }
        if (command === 'snapshot') {
          refs = new Map();
          const elements = [];
          const maxElements = Math.min(Math.max(Number(args.limit) || 250, 1), 1000);
          let truncated = false;
          for (const el of candidates(document)) {
            if (!visible(el)) continue;
            if (elements.length >= maxElements) { truncated = true; break; }
            const ref = `e${args.snapshotId}-${elements.length + 1}`;
            const elementRole = role(el);
            const entry = { ref: `@${ref}`, role: elementRole, name: name(el), disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true') };
            if (el.tagName === 'INPUT' && el.type === 'password') entry.sensitive = true;
            else if (['INPUT','TEXTAREA','SELECT'].includes(el.tagName) && !/^(file|hidden)$/.test(el.type || '')) entry.value = el.value;
            if (el.type === 'checkbox' || el.type === 'radio') entry.checked = el.checked;
            if (elementRole === 'heading') entry.level = Number(el.tagName.slice(1)) || Number(el.getAttribute('aria-level')) || 0;
            refs.set(ref, { element: el, fingerprint: fingerprint(el) });
            elements.push(entry);
          }
          const frameCount = document.querySelectorAll('iframe,frame').length;
          const maxChars = Math.min(Math.max(Number(args.maxChars) || 12000, 1), 100000);
          const rawText = document.body?.innerText || '';
          return { ok: true, data: { title: document.title, url: location.href, documentId, snapshotId: args.snapshotId,
            readyState: document.readyState, elements, text: rawText.slice(0, maxChars),
            truncated: truncated || rawText.length > maxChars, frameCount,
            limitations: frameCount ? ['iframe content requires human interaction in this version'] : [] } };
        }
        if (command === 'text') {
          const maxChars = Math.min(Math.max(Number(args.maxChars) || 16000, 1), 100000);
          const text = document.body?.innerText || '';
          return { ok: true, data: { title: document.title, url: location.href, text: text.slice(0, maxChars), truncated: text.length > maxChars } };
        }
        if (command === 'ready') return { ok: true, data: { ready: document.readyState !== 'loading', url: location.href } };
        if (command === 'exists') {
          let found;
          try { found = document.querySelector(args.selector); }
          catch { return failure('invalid_selector', 'Use a valid CSS selector.'); }
          return { ok: true, data: { found: Boolean(found && visible(found)) } };
        }
        if (command === 'scroll') {
          if (!['up','down','left','right'].includes(args.direction)) return failure('invalid_argument', 'Scroll direction must be up, down, left, or right.');
          const amount = Math.min(Math.max(Number(args.amount) || 500, 1), 10000);
          const container = args.ref ? resolve(args.ref) : window;
          const vertical = args.direction === 'up' || args.direction === 'down';
          const signed = (args.direction === 'up' || args.direction === 'left') ? -amount : amount;
          container.scrollBy({ left: vertical ? 0 : signed, top: vertical ? signed : 0, behavior: 'instant' });
          return { ok: true, data: { scrolled: true } };
        }
        const el = resolve(args.ref);
        el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
        el.focus({ preventScroll: true });
        if (command === 'click') {
          el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, composed: true }));
          el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, composed: true }));
          el.click();
        } else if (command === 'fill') {
          setValue(el, String(args.value ?? ''));
        } else if (command === 'select') {
          if (!(el instanceof HTMLSelectElement)) return failure('wrong_element_type', 'Use select on a select element.');
          const option = Array.from(el.options).find(option => option.value === args.value || clean(option.textContent) === args.value);
          if (!option) return failure('option_not_found', 'No option matches that value or label.');
          if (option.disabled || option.parentElement?.disabled) return failure('element_disabled', 'That option is disabled.');
          Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(el, option.value);
          events(el);
        } else if (command === 'check' || command === 'uncheck') {
          if (!(el instanceof HTMLInputElement) || !['checkbox','radio'].includes(el.type)) return failure('wrong_element_type', 'Use check on a checkbox or radio input.');
          if (el.type === 'radio' && command === 'uncheck') return failure('unsupported_input', 'Select another radio option instead.');
          if (el.checked !== (command === 'check')) el.click();
        } else if (command === 'press') {
          const key = args.key;
          if (!['Enter','Tab','Escape','Backspace','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space'].includes(key)) return failure('unsupported_key', 'Supported keys: Enter, Tab, Escape, Backspace, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, Space.');
          const eventKey = key === 'Space' ? ' ' : key;
          const prevented = !el.dispatchEvent(new KeyboardEvent('keydown', { key: eventKey, bubbles: true, composed: true, cancelable: true }));
          if (!prevented) {
            if (key === 'Enter') {
              if (role(el) === 'button' || role(el) === 'link') el.click();
              else if (el.form) el.form.requestSubmit();
            } else if (key === 'Space' && ['button','checkbox','radio'].includes(role(el))) el.click();
            else if (key === 'Tab') {
              const focusable = candidates(document).filter(item => visible(item) && !item.disabled && item.tabIndex >= 0);
              focusable[(focusable.indexOf(el) + 1) % focusable.length]?.focus();
            } else if (key === 'Backspace' && (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement)) {
              const start = el.selectionStart, end = el.selectionEnd;
              if (start === null || end === null) return failure('unsupported_input', 'This field does not support text selection.');
              const position = start === end ? Math.max(0, start - 1) : start;
              setValue(el, el.value.slice(0, position) + el.value.slice(end));
              el.setSelectionRange(position, position);
            }
          }
          el.dispatchEvent(new KeyboardEvent('keyup', { key: eventKey, bubbles: true, composed: true }));
        } else return failure('unsupported_command', `Unknown page action: ${command}`);
        return { ok: true, data: { performed: command, ref: args.ref, inputMode: 'dom' } };
      } catch (error) {
        return failure(error.code || 'page_action_failed', error.message || 'The page action failed.');
      }
    }
  };
})();
