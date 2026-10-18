const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const directory = __dirname;

function exportedNames(source) {
  const names = new Set();
  for (const match of source.matchAll(
    /^export\s+(?:async\s+)?(?:function|const|let|var|class)\s+([A-Za-z_$][\w$]*)/gm,
  )) {
    names.add(match[1]);
  }
  for (const match of source.matchAll(/^export\s*\{([^}]*)\}/gm)) {
    for (const part of match[1].split(',')) {
      const name = part.trim().split(/\s+as\s+/).pop().trim();
      if (/^[A-Za-z_$][\w$]*$/.test(name)) names.add(name);
    }
  }
  return names;
}

function boundNames(source) {
  const bound = new Set();
  const addAll = (text) => {
    for (const match of text.matchAll(/[A-Za-z_$][\w$]*/g)) bound.add(match[0]);
  };
  for (const match of source.matchAll(
    /(?:async\s+)?function\s*[A-Za-z_$\w]*\s*\(([^)]*)\)/g,
  )) {
    addAll(match[1]);
  }
  for (const match of source.matchAll(/\(([^()]*)\)\s*=>/g)) addAll(match[1]);
  for (const match of source.matchAll(/(?:^|[^.\w$])([A-Za-z_$][\w$]*)\s*=>/g)) {
    bound.add(match[1]);
  }
  for (const match of source.matchAll(
    /(?:^|\s)(?:function|class|const|let|var)\s+([A-Za-z_$][\w$]*)/g,
  )) {
    bound.add(match[1]);
  }
  for (const match of source.matchAll(/(?:const|let|var)\s*\{([^}]*)\}/g)) {
    for (const part of match[1].split(',')) {
      const name = part.split('=')[0].split(':').pop().trim();
      if (/^[A-Za-z_$][\w$]*$/.test(name)) bound.add(name);
    }
  }
  for (const match of source.matchAll(/(?:const|let|var)\s*\[([^\]]*)\]/g)) {
    addAll(match[1]);
  }
  for (const match of source.matchAll(
    /(?:^|\s)for\s*\(\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g,
  )) {
    bound.add(match[1]);
  }
  for (const match of source.matchAll(/catch\s*\(\s*([A-Za-z_$][\w$]*)/g)) {
    bound.add(match[1]);
  }
  for (const match of source.matchAll(
    /^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)/gm,
  )) {
    bound.add(match[1]);
  }
  return bound;
}

function collect() {
  const files = fs.readdirSync(directory).filter((name) => name.endsWith('.js'));
  const sources = new Map();
  const exportsByFile = new Map();
  for (const file of files) {
    const source = fs.readFileSync(path.join(directory, file), 'utf8');
    sources.set(file, source);
    exportsByFile.set(file, exportedNames(source));
  }
  return {files, sources, exportsByFile};
}

test('every cross-module helper is imported where it is called', () => {
  const {files, sources, exportsByFile} = collect();
  const problems = [];
  for (const file of files) {
    const source = sources.get(file);
    if (!/^\s*(import|export)\s/m.test(source)) continue;
    const imported = new Set();
    for (const match of source.matchAll(/^import\s*\{([^}]*)\}\s*from/gm)) {
      for (const part of match[1].split(',')) {
        const name = part.trim().split(/\s+as\s+/).pop().trim();
        if (name) imported.add(name);
      }
    }
    for (const match of source.matchAll(/^import\s+([A-Za-z_$][\w$]*)\s+from/gm)) {
      imported.add(match[1]);
    }
    const bound = boundNames(source);
    const called = new Set();
    for (const match of source.matchAll(/(^|[^.\w$'"`])([A-Za-z_$][\w$]*)\s*\(/g)) {
      called.add(match[2]);
    }
    for (const other of files) {
      if (other === file) continue;
      for (const name of exportsByFile.get(other)) {
        if (!called.has(name) || imported.has(name) || bound.has(name)) continue;
        problems.push(
          `${file} 调用了 ${name}()，但它定义在 ${other} 且没有导入；浏览器会抛 "is not defined"`,
        );
      }
    }
  }
  assert.deepEqual(problems, []);
});

test('viewer helpers stay exported for the settings module', () => {
  const settings = fs.readFileSync(path.join(directory, 'settings.js'), 'utf8');
  assert.match(settings, /^import\s*\{[^}]*viewerHeaders[^}]*\}\s*from\s*'\.\/viewer\.js'/m);
  assert.match(settings, /^import\s*\{[^}]*checkViewerResponse[^}]*\}\s*from\s*'\.\/viewer\.js'/m);
  const viewer = fs.readFileSync(path.join(directory, 'viewer.js'), 'utf8');
  assert.match(viewer, /^export function viewerHeaders\(/m);
  assert.match(viewer, /^export function checkViewerResponse\(/m);
});
