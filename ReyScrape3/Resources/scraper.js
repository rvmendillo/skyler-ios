(() => {
  'use strict';
  if (globalThis.ReyScrape) return;
  let picking = false;
  let highlighted = null;
  let previousOutline = '';
  const clean = value => String(value ?? '').replace(/\s+/g, ' ').trim();
  const escape = value => CSS.escape(value);
  const classes = element => [...element.classList].filter(name =>
    name.length < 60 && !/^(active|selected|hover|focus|rs-)/i.test(name)
  ).slice(0, 3);
  const token = element => element.tagName.toLowerCase() + classes(element).map(c => '.' + escape(c)).join('');
  const select = (root, selector) => selector === ':scope' || !selector ? [root] : [...root.querySelectorAll(selector)];
  const url = (value, base = document.baseURI) => {
    if (!value) return '';
    try {
      const resolved = new URL(value, base);
      return ['https:', 'http:'].includes(resolved.protocol) ? resolved.href : '';
    } catch { return ''; }
  };
  function relativeSelector(element, ancestor) {
    if (element === ancestor) return ':scope';
    let current = element;
    const parts = [];
    while (current && current !== ancestor && current !== document.documentElement) {
      let part = token(current);
      if (current.parentElement) {
        const siblings = [...current.parentElement.children].filter(n => n.matches(part));
        if (siblings.length > 1) {
          const sameTag = [...current.parentElement.children].filter(n => n.tagName === current.tagName);
          part += ':nth-of-type(' + (sameTag.indexOf(current) + 1) + ')';
        }
      }
      parts.unshift(part);
      if (ancestor && select(ancestor, parts.join(' > ')).length === 1) break;
      current = current.parentElement;
    }
    return parts.join(' > ') || ':scope';
  }
  function guessRow(element) {
    for (let current = element.parentElement; current && current !== document.body; current = current.parentElement) {
      const candidate = token(current);
      if (['UL', 'OL', 'TABLE', 'TBODY', 'THEAD'].includes(current.tagName)) continue;
      const siblings = current.parentElement ? [...current.parentElement.children].filter(n => n.matches(candidate)) : [];
      if (siblings.length > 1 && siblings.length <= 1000) return { element: current, selector: candidate };
    }
    const candidate = token(element);
    if (document.querySelectorAll(candidate).length > 1) return { element, selector: candidate };
    return { element: document.body, selector: 'body' };
  }
  function clearHighlight() {
    if (highlighted) highlighted.style.outline = previousOutline;
    highlighted = null;
  }
  function pick(element, configuredRow) {
    let row = null;
    if (configuredRow) {
      try { row = element.closest(configuredRow); } catch { /* a fresh row will be suggested */ }
    }
    const inferred = row ? { element: row, selector: configuredRow } : guessRow(element);
    return {
      rowSelector: inferred.selector,
      selector: relativeSelector(element, inferred.element),
      text: clean(element.textContent).slice(0, 240),
      tag: element.tagName.toLowerCase(),
      kind: element.matches('img') ? 'image' : 'text',
      count: document.querySelectorAll(inferred.selector).length,
      inferred: !row
    };
  }
  const api = {
    rowSelector: '',
    publicProfile(html) {
      // A detached template is inert. No downloaded page scripts or resources are executed.
      const template = document.createElement('template');
      template.innerHTML = html;
      const doc = template.content;
      const persons = [];
      const walk = (value, depth = 0) => {
        if (!value || depth > 8) return;
        if (Array.isArray(value)) { value.slice(0, 100).forEach(v => walk(v, depth + 1)); return; }
        if (typeof value !== 'object') return;
        const types = Array.isArray(value['@type']) ? value['@type'] : [value['@type']];
        if (types.some(t => t === 'Person' || t === 'https://schema.org/Person')) persons.push(value);
        if (value['@graph']) walk(value['@graph'], depth + 1);
        if (value.mainEntity) walk(value.mainEntity, depth + 1);
      };
      for (const node of [...doc.querySelectorAll('script[type="application/ld+json"]')].slice(0, 30)) {
        try { walk(JSON.parse(node.textContent)); } catch { /* ignore invalid metadata */ }
      }
      if (persons.length > 1) throw new Error('This page describes multiple people. Use one direct public profile page.');
      const person = persons[0] || {};
      const scalar = value => typeof value === 'string' || typeof value === 'number' ? clean(value) : '';
      const publicText = value => scalar(value).slice(0, 400)
        .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '[contact omitted]')
        .replace(/(?:\+?\d[\s().-]*){8,}/g, '[contact omitted]');
      const names = value => (Array.isArray(value) ? value : [value]).slice(0, 20)
        .map(v => publicText(typeof v === 'object' && v ? v.name : v)).filter(Boolean);
      const meta = property => publicText(doc.querySelector('meta[property="' + property + '"]')?.getAttribute('content'));
      // Explicit professional-field allowlist: no contact details, location, family, demographics, or biography.
      return {
        name: publicText(person.name) || [meta('profile:first_name'), meta('profile:last_name')].filter(Boolean).join(' '),
        pageTitle: publicText(doc.querySelector('title')?.textContent) || meta('og:title'),
        role: names(person.jobTitle).join(' · '),
        organization: names(person.worksFor).join(' · '),
        skills: names(person.knowsAbout),
        structured: persons.length === 1
      };
    },
    setPicking(enabled, rowSelector) {
      picking = !!enabled;
      api.rowSelector = rowSelector || '';
      if (!picking) clearHighlight();
      return picking;
    },
    describe(element, rowSelector) { return pick(element, rowSelector); },
    table() {
      const table = document.querySelector('table');
      if (!table) throw new Error('No HTML table found. Try selecting repeated items with Pick a column.');
      const tableSelector = table.id ? '#' + escape(table.id) : relativeSelector(table, document.body);
      const first = table.querySelector('tr');
      const cells = first ? [...first.children].filter(n => ['TD', 'TH'].includes(n.tagName)) : [];
      if (!cells.length) throw new Error('This table has no cells.');
      const header = cells.some(n => n.tagName === 'TH');
      const seen = new Set();
      const fields = cells.slice(0, 20).map((cell, index) => {
        let name = (header ? clean(cell.textContent) : '') || 'Column ' + (index + 1);
        if (seen.has(name)) name += ' ' + (index + 1);
        seen.add(name);
        return { name, selector: ':scope > :nth-child(' + (index + 1) + ')', kind: 'text', attribute: '', multiple: false };
      });
      return { rowSelector: tableSelector + (header ? ' tr:has(td)' : ' tr'), fields };
    },
    inspect(config) {
      const roots = [...document.querySelectorAll(config.rowSelector || 'body')];
      return { count: roots.length, checked: Math.min(roots.length, 50), fields: config.fields.map(field => ({ name: field.name, matched: roots.slice(0, 50).filter(root => select(root, field.selector).length > 0).length })) };
    },
    suggest() {
      if (document.querySelector('table')) return api.table();
      const choices = ['.product', '[itemtype$="Product"]', 'article', '.card', 'li'];
      const selector = choices.find(s => document.querySelectorAll(s).length >= 2);
      if (!selector) throw new Error('No clear repeated list found. Use Pick a column.');
      const first = document.querySelector(selector);
      const fields = [];
      const heading = ['.name', 'h2', 'h3', 'h4', 'a'].find(s => first.querySelector(s));
      fields.push({ name: 'Name', selector: heading || ':scope', kind: 'text' });
      const price = ['.price', '[itemprop="price"]', '[data-price]'].find(s => first.querySelector(s));
      if (price) fields.push({ name: 'Price', selector: price, kind: 'text' });
      if (first.querySelector('a[href]')) fields.push({ name: 'URL', selector: 'a[href]', kind: 'link' });
      if (first.querySelector('img')) fields.push({ name: 'Image', selector: 'img', kind: 'image' });
      return { rowSelector: selector, fields };
    },
    extractHTML(html, source, config) {
      const template = document.createElement('template');
      template.innerHTML = html;
      const result = api.extract(config, template.content, source);
      const next = template.content.querySelector(config.nextSelector || 'a[rel="next"],link[rel="next"]');
      return { ...result, nextURL: next ? url(next.getAttribute('href'), source) : '' };
    },
    extract(config, rootNode = document, base = document.baseURI) {
      if (!config || !Array.isArray(config.fields) || !config.fields.length) throw new Error('Add at least one column.');
      if (config.fields.length > 20) throw new Error('Use at most 20 columns.');
      const names = config.fields.map(f => clean(f.name));
      if (names.some(n => !n)) throw new Error('Give each column a name.');
      if (new Set(names).size !== names.length) throw new Error('Column names must be different.');
      let roots;
      try { roots = rootNode !== document && (!config.rowSelector || config.rowSelector === 'body') ? [rootNode] : [...rootNode.querySelectorAll(config.rowSelector || 'body')]; }
      catch { throw new Error('The repeated-item selector is invalid. Check it in Columns.'); }
      for (const field of config.fields) {
        try { if (field.selector && field.selector !== ':scope') document.createElement('div').querySelector(field.selector); }
        catch { throw new Error('Invalid selector for “' + field.name + '”.'); }
        if (field.kind === 'attribute' && !clean(field.attribute)) throw new Error('Enter an attribute name for “' + field.name + '”.');
      }
      const limit = 1000;
      const rows = roots.slice(0, limit).map(root => config.fields.map(field => {
        const nodes = select(root, field.selector);
        const selected = field.multiple ? nodes : nodes.slice(0, 1);
        return selected.map(node => {
          if (field.kind === 'link') return url(node.getAttribute?.('href'), base);
          if (field.kind === 'image') return url(node.currentSrc || node.getAttribute?.('src') || node.getAttribute?.('data-src'), base);
          if (field.kind === 'attribute') return clean(node.getAttribute?.(field.attribute)).slice(0, 10000);
          return clean(node.textContent).slice(0, 10000);
        }).filter(Boolean).join(' | ');
      }));
      return { columns: names, rows, matchedRows: roots.length, truncated: roots.length > limit };
    }
  };
  document.addEventListener('pointerover', event => {
    if (!picking || !(event.target instanceof Element)) return;
    clearHighlight();
    highlighted = event.target;
    previousOutline = highlighted.style.outline;
    highlighted.style.outline = '3px solid #6958ee';
  }, true);
  document.addEventListener('click', event => {
    if (!picking || !(event.target instanceof Element)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const result = pick(event.target, api.rowSelector);
    clearHighlight();
    picking = false;
    globalThis.webkit?.messageHandlers?.picked?.postMessage(result);
  }, true);
  globalThis.ReyScrape = api;
})();
