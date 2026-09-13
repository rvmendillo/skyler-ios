document.getElementById('send').addEventListener('click', async () => {
  const tabs = await browser.tabs.query({active: true, currentWindow: true});
  const url = tabs && tabs[0] && tabs[0].url;
  if (!url || !/^https?:/i.test(url)) return;
  window.location.href = `reydl://add?url=${encodeURIComponent(url)}&source=safari-popup`;
});
