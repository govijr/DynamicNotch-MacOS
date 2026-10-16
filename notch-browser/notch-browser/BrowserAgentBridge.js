(() => {
  if (globalThis.__notchAgent) return;
  let refs = new Map();
  let mediaRefs = new Map();
  let navigationEpoch = null;
  const documentId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  const registerFrame = (event = 'register') => {
    try { window.webkit?.messageHandlers?.notchAgentFrames?.postMessage({ event, documentId, title: document.title, url: location.href }); }
    catch { /* Frame registration is available only in the native agent world. */ }
  };
  const failure = (code, message) => ({ ok: false, error: { code, message } });
  const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
  const visible = element => {
    if (!element.isConnected || element.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && element.getClientRects().length > 0;
  };
  const challengeURL = value => {
    try {
      const url = new URL(value, location.href), host = url.hostname;
      return ((host === 'www.google.com' || host === 'www.recaptcha.net' || host === 'www.recaptcha.google.com') && url.pathname.startsWith('/recaptcha/'))
        || host === 'hcaptcha.com' || host.endsWith('.hcaptcha.com') || host === 'challenges.cloudflare.com';
    } catch { return false; }
  };
  const challengeDocument = () => challengeURL(location.href) || Boolean(document.querySelector('#challenge-form,#cf-challenge-running'));
  const challengeState = () => {
    const blockers = [];
    if (challengeDocument()) blockers.push({ kind: 'captcha', requiresUser: true, url: location.href, message: 'This document is a human-verification challenge.' });
    for (const element of document.querySelectorAll('iframe[src],.g-recaptcha,.h-captcha,.cf-turnstile')) {
      if (visible(element) && (element.localName !== 'iframe' || challengeURL(element.src))) {
        blockers.push({ kind: 'captcha', requiresUser: true, url: element.src || location.href,
          message: 'A verification widget is present. The user must handle any challenge; its completion is not inferred.' });
      }
      if (blockers.length >= 20) break;
    }
    return { challengeDocument: challengeDocument(), blockers };
  };
  const pageText = () => {
    let text = document.body?.innerText || '';
    for (const field of document.querySelectorAll('[name="g-recaptcha-response"],[name="h-captcha-response"],[name="cf-turnstile-response"]')) {
      if (field.value) text = text.split(field.value).join('[redacted]');
    }
    return text;
  };
  const role = el => {
    if (el.getAttribute('role')) return el.getAttribute('role').split(' ')[0];
    const tag = el.tagName.toLowerCase();
    if (tag === 'a' && el.hasAttribute('href')) return 'link';
    if (tag === 'button' || (tag === 'input' && /^(button|submit|reset|image)$/.test(el.type))) return 'button';
    if (tag === 'input' && el.type === 'file') return 'file-upload';
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
  const mediaSource = el => el.currentSrc || el.getAttribute('src') || '';
  const mediaFingerprint = el => JSON.stringify([el.currentSrc, el.getAttribute('src'),
    ...Array.from(el.querySelectorAll('source')).map(source => source.getAttribute('src'))]);
  const extract = args => {
    let root;
    if (args.selector) {
      try { root = document.querySelector(args.selector); }
      catch { return failure('invalid_selector', 'Use a valid CSS selector.'); }
      if (!root || !visible(root)) return failure('element_not_found', 'The extraction selector did not match a visible element.');
    } else {
      root = Array.from(document.querySelectorAll('main,[role="main"],article')).find(visible) || document.body;
    }
    if (!root) return failure('empty_page', 'This page has no readable document.');
    const limit = Math.min(Math.max(Number(args.limit) || 50, 1), 50);
    const maxChars = Math.min(Math.max(Number(args.maxChars) || 12000, 1), 100000);
    let truncated = false;
    const clip = (value, length = 500) => {
      const text = clean(value);
      if (text.length > length) truncated = true;
      return text.slice(0, length);
    };
    const url = (value, blob = false) => {
      if (typeof value !== 'string' || !value) return null;
      try {
        const result = new URL(value, document.baseURI);
        if (!['http:', 'https:', 'file:', ...(blob ? ['blob:'] : [])].includes(result.protocol)) return null;
        result.username = ''; result.password = '';
        if (result.href.length > 4096) { truncated = true; return null; }
        return result.href;
      } catch { return null; }
    };
    const collect = (nodes, convert, cap = limit) => {
      const items = [], seen = new Set();
      for (const node of nodes) {
        const value = convert(node);
        if (!value) continue;
        const key = JSON.stringify(value);
        if (seen.has(key)) continue;
        if (items.length >= cap) { truncated = true; break; }
        seen.add(key); items.push(value);
      }
      return items;
    };
    const matching = selector => [...(root.matches(selector) ? [root] : []), ...root.querySelectorAll(selector)];
    const ignored = 'script,style,noscript,template,svg,canvas,input,textarea,select,button,nav,[role="navigation"],[hidden],[inert],[aria-hidden="true"]';
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const parts = [];
    let textLength = 0, scanned = 0, node;
    while ((node = walker.nextNode())) {
      if (++scanned > 20000) { truncated = true; break; }
      const parent = node.parentElement;
      if (!parent || parent.closest(ignored) || !visible(parent)) continue;
      const value = clean(node.nodeValue);
      if (!value) continue;
      const remaining = maxChars - textLength;
      if (remaining <= 0) { truncated = true; break; }
      parts.push(value.slice(0, remaining));
      textLength += Math.min(value.length, remaining) + 1;
      if (value.length > remaining) { truncated = true; break; }
    }
    const meta = names => {
      for (const name of names) {
        const element = Array.from(document.head?.querySelectorAll('meta[name],meta[property]') || [])
          .find(el => (el.getAttribute('name') || el.getAttribute('property'))?.toLowerCase() === name);
        if (element?.content) return clip(element.content, 2000);
      }
      return null;
    };
    const metadata = {
      description: meta(['og:description', 'description', 'twitter:description']),
      author: meta(['author', 'article:author']), siteName: meta(['og:site_name']),
      publishedAt: meta(['article:published_time', 'date']),
      image: url(meta(['og:image', 'twitter:image'])), video: url(meta(['og:video', 'og:video:url']))
    };
    const headings = collect(matching('h1,h2,h3,h4,h5,h6,[role="heading"]'), el => visible(el)
      ? { level: Number(el.tagName.slice(1)) || Number(el.getAttribute('aria-level')) || 0, text: clip(el.innerText) } : null);
    const links = collect(matching('a[href]'), el => visible(el) && url(el.href)
      ? { text: clip(el.innerText || el.getAttribute('aria-label')), url: url(el.href) } : null);
    const images = collect(matching('img'), el => visible(el) && url(el.currentSrc || el.src)
      ? { url: url(el.currentSrc || el.src), alt: clip(el.alt), width: el.naturalWidth || el.width, height: el.naturalHeight || el.height } : null);
    const limitations = ['Only currently loaded page content is extracted; this command does not scroll, fetch media, or transcribe audio.'];
    const frames = matching('iframe,frame').length;
    if (frames) limitations.push(`${frames} embedded frame(s) are not included.`);
    if (Array.from(root.querySelectorAll('*')).some(el => el.shadowRoot)) limitations.push('Shadow-root content is not included in extraction; use snapshot for interactive elements.');
    const structuredData = [], transcripts = [];
    let transcriptBudget = maxChars, jsonBudget = 500000;
    const transcriptText = value => {
      const text = clean(value);
      if (text.length > transcriptBudget) truncated = true;
      const result = text.slice(0, transcriptBudget);
      transcriptBudget -= result.length;
      return result;
    };
    const objectName = value => clip(typeof value === 'string' ? value : Array.isArray(value)
      ? value.map(v => typeof v === 'string' ? v : v?.name || '').join(', ') : value?.name || '');
    const metadataScripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
    if (metadataScripts.length > 20) truncated = true;
    for (const script of metadataScripts.slice(0, 20)) {
      const source = script.textContent || '';
      if (source.length > 250000 || source.length > jsonBudget) { truncated = true; continue; }
      jsonBudget -= source.length;
      let parsed;
      try { parsed = JSON.parse(source); }
      catch { limitations.push('A publisher structured-data block could not be parsed.'); continue; }
      const queue = [{ value: parsed, depth: 0 }];
      let visited = 0;
      while (queue.length && visited++ < 200) {
        const { value, depth } = queue.shift();
        if (!value || typeof value !== 'object') continue;
        if (depth > 8) { truncated = true; continue; }
        if (Array.isArray(value)) {
          if (value.length > 50) truncated = true;
          queue.push(...value.slice(0, 50).map(v => ({ value: v, depth: depth + 1 }))); continue;
        }
        const types = [].concat(value['@type'] || []);
        if (types.some(type => ['Article', 'NewsArticle', 'BlogPosting', 'SocialMediaPosting', 'VideoObject', 'AudioObject', 'ImageObject'].includes(type))) {
          if (structuredData.length >= Math.min(limit, 10)) { truncated = true; break; }
          structuredData.push({ type: types.filter(v => typeof v === 'string').slice(0, 4), name: clip(value.name || value.headline),
            description: clip(value.description, 2000), author: objectName(value.author), publishedAt: clip(value.datePublished || value.uploadDate),
            duration: clip(value.duration), url: url(value.url), contentURL: url(value.contentUrl), embedURL: url(value.embedUrl),
            thumbnailURL: url([].concat(value.thumbnailUrl || [])[0]) });
          if (typeof value.transcript === 'string' && transcriptBudget > 0) {
            const text = transcriptText(value.transcript);
            if (text) transcripts.push({ source: 'publisher-structured-data', text });
          }
        }
        for (const key of ['@graph', 'mainEntity', 'video', 'audio', 'associatedMedia', 'image', 'subjectOf']) {
          if (value[key]) queue.push({ value: value[key], depth: depth + 1 });
        }
      }
      if (queue.length) truncated = true;
    }
    mediaRefs = new Map();
    const media = collect(matching('video,audio'), el => {
      if (!visible(el)) return null;
      const source = url(mediaSource(el), true);
      const ref = `@m${args.extractionId}-${mediaRefs.size + 1}`;
      mediaRefs.set(ref, { element: el, fingerprint: mediaFingerprint(el), stream: el.srcObject });
      if (el.textTracks.length > 4) truncated = true;
      const tracks = Array.from(el.textTracks || []).slice(0, 4).map(track => {
        const cues = [];
        if (['captions', 'subtitles'].includes(track.kind)) {
          for (const cue of Array.from(track.cues || [])) {
            if (cues.length >= 200 || transcriptBudget <= 0) { truncated = true; break; }
            const text = transcriptText(cue.text || '');
            if (text) cues.push({ start: cue.startTime, end: cue.endTime, text });
          }
        }
        return { kind: track.kind, language: track.language, label: clip(track.label), mode: track.mode,
          availability: cues.length ? 'loaded-cues' : 'unavailable', cues };
      });
      const protectedMedia = Boolean(el.mediaKeys || el.webkitKeys);
      return { ref, kind: el.localName, source, sourceType: source?.startsWith('blob:') ? 'blob' : source ? 'url' : 'unavailable',
        poster: url(el.poster), label: clip(el.getAttribute('aria-label') || el.title),
        duration: Number.isFinite(el.duration) ? el.duration : null, currentTime: Number.isFinite(el.currentTime) ? el.currentTime : null,
        paused: el.paused, readyState: el.readyState, width: el.videoWidth || null, height: el.videoHeight || null,
        protected: protectedMedia, tracks,
        trackURLs: Array.from(el.querySelectorAll('track[src]')).slice(0, 4).map(track => ({ kind: track.kind, language: track.srclang, url: url(track.src) })) };
    }, Math.min(limit, 10));
    // collect() probes one extra item to report truncation. Only returned refs remain valid.
    const returnedRefs = new Set(media.map(item => item.ref));
    for (const ref of mediaRefs.keys()) if (!returnedRefs.has(ref)) mediaRefs.delete(ref);
    if (media.some(item => item.sourceType === 'blob')) limitations.push('Blob media URLs belong to this tab and are not downloadable file URLs.');
    if (media.some(item => item.protected)) limitations.push('Protected media cannot be captured.');
    const hasTranscript = transcripts.length > 0 || media.some(item => item.tracks.some(track => track.cues.length));
    if (media.length && !hasTranscript) limitations.push('No loaded captions or publisher transcript were available; audio has not been transcribed.');
    return { ok: true, data: { schemaVersion: 1, extractionId: args.extractionId, title: clip(document.title, 2000), url: location.href,
      canonicalURL: url(document.querySelector('link[rel="canonical"]')?.href), language: document.documentElement.lang || null,
      scope: args.selector || root.tagName.toLowerCase(), text: parts.join('\n').slice(0, maxChars), metadata,
      headings, links, images, media, structuredData, transcripts, transcriptAvailable: hasTranscript,
      truncated, limitations: [...new Set(limitations)] } };
  };
  const mediaFrame = args => {
    const saved = mediaRefs.get(args.ref);
    if (!saved || !saved.element.isConnected || saved.fingerprint !== mediaFingerprint(saved.element)
      || saved.stream !== saved.element.srcObject) return failure('stale_ref', 'Run extract again and use its latest media reference.');
    const el = saved.element;
    if (el.localName !== 'video') return failure('wrong_element_type', 'Only video elements have image frames.');
    if (el.mediaKeys || el.webkitKeys) return failure('media_protected', 'Protected media cannot be captured.');
    if (el.readyState < 2 || !el.videoWidth || !el.videoHeight) return failure('frame_unavailable', 'The video has no decoded frame. Start playback, then extract again.');
    const scale = Math.min(1, 1280 / Math.max(el.videoWidth, el.videoHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(el.videoWidth * scale));
    canvas.height = Math.max(1, Math.round(el.videoHeight * scale));
    try {
      canvas.getContext('2d').drawImage(el, 0, 0, canvas.width, canvas.height);
      return { ok: true, data: { png: canvas.toDataURL('image/png').split(',')[1], width: canvas.width, height: canvas.height,
        currentTime: el.currentTime, ref: args.ref } };
    } catch (error) {
      if (error.name === 'SecurityError') return failure('frame_access_denied', 'This site prevents direct frame capture. Use screenshot to inspect the rendered page instead.');
      return failure('frame_unavailable', 'The current video frame could not be captured.');
    }
  };
  globalThis.__notchAgent = {
    run(command, args = {}) {
      try {
        if (args.frameDocumentId && args.frameDocumentId !== documentId) return failure('frame_gone', 'This frame navigated. Run frames again.');
        // WebKit may restore an old JS world from its back/forward cache.
        // The native epoch still changes, so references cannot survive a trip
        // away from this document and back again.
        if (navigationEpoch !== args.documentEpoch) {
          refs = new Map();
          mediaRefs = new Map();
          navigationEpoch = args.documentEpoch;
        }
        if (command === 'extract') return extract(args);
        if (command === 'media-frame') return mediaFrame(args);
        if (command === 'identify') return { ok: true, data: { documentId, title: document.title, url: location.href } };
        if (command === 'challenge-state') return { ok: true, data: challengeState() };
        if (challengeDocument() && !['snapshot', 'text', 'extract', 'ready', 'exists'].includes(command)) {
          return failure('human_required', 'Human verification requires the user. Run handoff; CAPTCHA solving is not automated.');
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
            if (el.tagName === 'INPUT' && el.type === 'file') {
              entry.multiple = el.multiple; entry.accept = el.accept;
              entry.files = Array.from(el.files || []).slice(0, 100).map(file => file.name);
            }
            if ((el.tagName === 'INPUT' && el.type === 'password') || el.matches('[name="g-recaptcha-response"],[name="h-captcha-response"],[name="cf-turnstile-response"]')) entry.sensitive = true;
            else if (['INPUT','TEXTAREA','SELECT'].includes(el.tagName) && !/^(file|hidden)$/.test(el.type || '')) entry.value = el.value;
            if (el.type === 'checkbox' || el.type === 'radio') entry.checked = el.checked;
            if (elementRole === 'heading') entry.level = Number(el.tagName.slice(1)) || Number(el.getAttribute('aria-level')) || 0;
            refs.set(ref, { element: el, fingerprint: fingerprint(el) });
            elements.push(entry);
          }
          const frameCount = document.querySelectorAll('iframe,frame').length;
          const maxChars = Math.min(Math.max(Number(args.maxChars) || 12000, 1), 100000);
          const rawText = pageText();
          return { ok: true, data: { title: document.title, url: location.href, documentId, snapshotId: args.snapshotId,
            readyState: document.readyState, elements, text: rawText.slice(0, maxChars),
            truncated: truncated || rawText.length > maxChars, frameCount,
            limitations: frameCount ? ['Embedded frames have separate snapshots; run frames and target one with --frame.'] : [] } };
        }
        if (command === 'text') {
          const maxChars = Math.min(Math.max(Number(args.maxChars) || 16000, 1), 100000);
          const text = pageText();
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
        if (el.closest('.g-recaptcha,.h-captcha,.cf-turnstile,[data-sitekey]')) {
          return failure('human_required', 'Verification controls require the user. Run handoff.');
        }
        if (command === 'file-info') {
          if (!(el instanceof HTMLInputElement) || el.type !== 'file') return failure('wrong_element_type', 'Use upload on a file input reference.');
          return { ok: true, data: { url: location.href, multiple: el.multiple, accept: el.accept,
            files: Array.from(el.files || []).slice(0, 100).map(file => ({ name: file.name, size: file.size, type: file.type })) } };
        }
        el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
        el.focus({ preventScroll: true });
        if (command === 'upload-trigger') {
          if (!(el instanceof HTMLInputElement) || el.type !== 'file') return failure('wrong_element_type', 'Use upload on a file input reference.');
          el.click();
        } else if (command === 'click') {
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
  registerFrame();
  document.addEventListener('DOMContentLoaded', () => registerFrame());
  window.addEventListener('pageshow', () => registerFrame());
  window.addEventListener('pagehide', () => registerFrame('remove'));
})();
