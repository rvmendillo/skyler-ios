(() => {
  const fileLike = /\.(7z|zip|rar|tar|gz|tgz|bz2|xz|bin|dmg|pkg|ipa|apk|exe|msi|pdf|epub|mobi|mp3|m4a|aac|wav|flac|ogg|mp4|m4v|mkv|mov|avi|webm|iso|img|csv|tsv|json|xml|txt|rtf|docx?|xlsx?|pptx?|pages|numbers|key)(?:$|[?#])/i;
  const downloadHint = /(?:^|[\/?&=_-])(download|downloads|attachment|attachments|export|file|files|media|document|archive|asset|dl)(?:$|[\/?&=_-])/i;
  const downloadQuery = /[?&](?:download|dl|attachment|export|filename|file)=/i;

  function absoluteURL(value) {
    try { return new URL(value, document.baseURI).href; } catch (_) { return null; }
  }

  function isHTTP(url) {
    return /^https?:/i.test(url || '');
  }

  function looksDownloadable(url, anchor) {
    if (!isHTTP(url)) return false;
    if (anchor && anchor.hasAttribute && anchor.hasAttribute('download')) return true;
    if (fileLike.test(url) || downloadQuery.test(url)) return true;
    try {
      const parsed = new URL(url);
      return downloadHint.test(parsed.pathname);
    } catch (_) {
      return false;
    }
  }

  function handoff(url, name) {
    if (!isHTTP(url)) return false;
    const target = `reydl://add?url=${encodeURIComponent(url)}${name ? `&name=${encodeURIComponent(name)}` : ''}&source=safari`;
    window.location.assign(target);
    return true;
  }

  function captureAnchor(anchor) {
    if (!anchor) return false;
    const url = absoluteURL(anchor.href || anchor.getAttribute('href'));
    if (!looksDownloadable(url, anchor)) return false;
    return handoff(url, anchor.getAttribute('download') || '');
  }

  for (const eventName of ['click', 'auxclick']) {
    document.addEventListener(eventName, (event) => {
      const anchor = event.target && event.target.closest ? event.target.closest('a[href], area[href]') : null;
      if (!anchor || !captureAnchor(anchor)) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    }, true);
  }

  const nativeAnchorClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(...args) {
    if (captureAnchor(this)) return;
    return nativeAnchorClick.apply(this, args);
  };

  const nativeOpen = window.open;
  window.open = function(url, target, features) {
    const resolved = typeof url === 'string' ? absoluteURL(url) : null;
    if (resolved && looksDownloadable(resolved, null) && handoff(resolved, '')) return null;
    return nativeOpen.call(window, url, target, features);
  };

  document.addEventListener('submit', (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    const method = (form.method || 'get').toLowerCase();
    if (method !== 'get') return;
    const action = absoluteURL(form.action || location.href);
    if (!action || !downloadHint.test(new URL(action).pathname)) return;
    const params = new URLSearchParams(new FormData(form));
    const target = new URL(action);
    for (const [key, value] of params.entries()) target.searchParams.append(key, String(value));
    if (handoff(target.href, '')) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);
})();
