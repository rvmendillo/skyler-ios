(() => {
  const fileLike = /\.(7z|zip|rar|tar|gz|bz2|xz|dmg|pkg|ipa|apk|exe|msi|pdf|epub|mp3|m4a|wav|flac|mp4|m4v|mkv|mov|avi|webm|iso|img|csv|json|xml|docx?|xlsx?|pptx?)(?:$|[?#])/i;

  function handoff(url, name) {
    if (!/^https?:/i.test(url)) return false;
    const target = `reydl://add?url=${encodeURIComponent(url)}${name ? `&name=${encodeURIComponent(name)}` : ''}&source=safari`;
    window.location.assign(target);
    return true;
  }

  document.addEventListener('click', (event) => {
    const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
    if (!anchor) return;
    const url = anchor.href;
    const shouldCapture = anchor.hasAttribute('download') || fileLike.test(url);
    if (!shouldCapture) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    handoff(url, anchor.getAttribute('download') || '');
  }, true);
})();
