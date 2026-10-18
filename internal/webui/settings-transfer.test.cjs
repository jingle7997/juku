const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {pathToFileURL} = require('node:url');

const directory = __dirname;

class StubElement {
  constructor(id) {
    this.id = id;
    this.textContent = '';
    this.disabled = false;
    this.hidden = false;
    this.value = '';
    this.children = [];
    this.style = {};
    this.dataset = {};
    this.files = null;
    this.href = '';
    this.download = '';
    this.classList = {add() {}, remove() {}, toggle() {}, contains: () => false};
  }
  addEventListener(type, handler) {
    (this.handlers ||= {})[type] = handler;
  }
  replaceChildren(...children) {
    this.children = children;
  }
  appendChild(child) {
    this.children.push(child);
    return child;
  }
  querySelector() {
    return null;
  }
  querySelectorAll() {
    return [];
  }
  setAttribute(key, value) {
    this[key] = value;
  }
  getAttribute(key) {
    return this[key];
  }
  focus() {}
  remove() {}
  closest() {
    return null;
  }
  click() {
    globalThis.__downloaded = {name: this.download, href: this.href};
  }
}

function installBrowserStubs() {
  const elements = new Map();
  const calls = [];
  globalThis.window = globalThis;
  globalThis.addEventListener = () => {};
  globalThis.removeEventListener = () => {};
  globalThis.document = {
    getElementById: (id) => {
      if (!elements.has(id)) elements.set(id, new StubElement(id));
      return elements.get(id);
    },
    querySelector: () => null,
    querySelectorAll: () => [],
    createElement: () => new StubElement('created'),
    body: new StubElement('body'),
    documentElement: new StubElement('html'),
    addEventListener: () => {},
  };
  globalThis.location = {href: 'http://127.0.0.1/', origin: 'http://127.0.0.1', search: '', pathname: '/'};
  Object.defineProperty(globalThis, 'navigator', {
    value: {userAgent: 'node'},
    configurable: true,
  });
  globalThis.localStorage = {getItem: () => null, setItem() {}, removeItem() {}};
  globalThis.CustomEvent = class {
    constructor(type, options) {
      this.type = type;
      Object.assign(this, options);
    }
  };
  globalThis.Event = globalThis.CustomEvent;
  globalThis.requestAnimationFrame = (callback) => setTimeout(callback, 0);
  globalThis.matchMedia = () => ({
    matches: false,
    addEventListener() {},
    addListener() {},
  });
  globalThis.URL.createObjectURL = () => 'blob:stub';
  globalThis.URL.revokeObjectURL = () => {};
  globalThis.JukuTheme = {get: () => 'system', set() {}};
  globalThis.JukuDialogs = {open() {}, close() {}};
  globalThis.fetch = async (url, init) => {
    calls.push({url: String(url), init: init || {}});
    if (String(url).includes('/api/ui/admin/library')) {
      return {
        ok: true,
        status: 200,
        headers: {get: (key) => (key === 'X-Juku-Library-Count' ? '7' : null)},
        blob: async () => ({size: 8, type: 'application/x-xz'}),
        json: async () => ({imported: 0, merged: 0, total: 0, sources: {}}),
        text: async () => '',
      };
    }
    return {
      ok: true,
      status: 200,
      headers: {get: () => null},
      json: async () => ({id: 'viewer'}),
      text: async () => '',
    };
  };
  return {elements, calls};
}

async function loadSettings() {
  const {elements, calls} = installBrowserStubs();
  const base = pathToFileURL(directory + path.sep).href;
  // library-transfer.js 在页面里由普通 <script> 标签加载并挂到 window 上；
  // 这里用 require 取同一对象，避免 ESM 缓存导致重复导入不再执行。
  globalThis.JukuLibraryTransfer = require(path.join(directory, 'library-transfer.js'));
  const settings = await import(`${base}settings.js`);
  const app = {
    library: {refresh: async () => {}, all: () => []},
    refresh: async () => {},
  };
  const api = settings.createSettings(app);
  app.viewer = {account: {admin: true, requirePasswordChange: false}};
  // init 在返回前会读取完整配置（依赖真实 DOM），但按钮绑定发生在此之前，
  // 因此同步调用即可，不等待它返回的 Promise。
  let pending;
  try {
    pending = api.init();
  } catch (error) {
    throw new Error('设置页初始化失败，无法验证剧库按钮绑定：' + error.message);
  }
  if (pending && typeof pending.catch === 'function') pending.catch(() => {});
  return {api, app, elements, calls};
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 30));

test('exporting a library requests an xz package and reports the count', async () => {
  const {elements, calls} = await loadSettings();
  const button = elements.get('libraryExportBtn');
  assert.equal(typeof button?.handlers?.click, 'function', '导出按钮没有绑定点击处理');
  await button.handlers.click();
  await settle();
  const status = elements.get('libraryTransferStatus').textContent;
  assert.doesNotMatch(status, /is not defined/, `导出路径抛出了未定义引用：${status}`);
  assert.doesNotMatch(status, /^导出失败/, `导出失败：${status}`);
  assert.match(status, /已导出 7 部剧库条目/);
  const request = calls.find((call) => call.url.includes('/api/ui/admin/library'));
  assert.ok(request, '没有发出剧库导出请求');
  const headers = request.init.headers || {};
  assert.equal(headers.Accept, 'application/x-xz');
  assert.equal(globalThis.__downloaded?.name, '剧库-' + new Date().toISOString().substring(0, 10) + '.xz');
});

test('importing keeps xz binary and legacy json as separate content types', async () => {
  const {elements, calls} = await loadSettings();
  const input = elements.get('libraryImportFile');
  assert.equal(typeof input?.handlers?.change, 'function', '导入文件输入没有绑定处理');
  const xzBytes = Uint8Array.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 9, 9]);
  await input.handlers.change({target: {files: [{arrayBuffer: async () => xzBytes.buffer}]}});
  await settle();
  const xzStatus = elements.get('libraryTransferStatus').textContent;
  assert.doesNotMatch(xzStatus, /is not defined/, `xz 导入抛出了未定义引用：${xzStatus}`);
  assert.doesNotMatch(xzStatus, /^导入失败/, `xz 导入失败：${xzStatus}`);

  const json = Buffer.from(
    JSON.stringify({
      app: 'juku',
      kind: 'library',
      version: 1,
      count: 1,
      dramas: [{id: 'hongguo:1', source: 'hongguo'}],
    }),
  );
  await input.handlers.change({
    target: {
      files: [
        {
          arrayBuffer: async () =>
            json.buffer.slice(json.byteOffset, json.byteOffset + json.byteLength),
        },
      ],
    },
  });
  await settle();
  const jsonStatus = elements.get('libraryTransferStatus').textContent;
  assert.doesNotMatch(jsonStatus, /is not defined/, `json 导入抛出了未定义引用：${jsonStatus}`);
  assert.doesNotMatch(jsonStatus, /^导入失败/, `json 导入失败：${jsonStatus}`);

  const posts = calls.filter((call) => call.init.method === 'POST');
  assert.equal(posts.length, 2);
  assert.equal(posts[0].init.headers['Content-Type'], 'application/x-xz');
  assert.equal(posts[1].init.headers['Content-Type'], 'application/json');
});
