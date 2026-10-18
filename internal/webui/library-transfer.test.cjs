const test = require('node:test');
const assert = require('node:assert/strict');
const {parseLibraryPackage, libraryPackageIsXZ, normalizeLibraryPackage, libraryPackageFileName, libraryImportSummary, maxEntries, maxBytes} = require('./library-transfer.js');

test('package parsing accepts the shared exchange format and reports the entry count', () => {
  const pack = parseLibraryPackage(JSON.stringify({app: 'zhenguojian', kind: 'library', version: 1, count: 2, dramas: [{id: 'hongguo:1'}, {id: 'huangdou:2'}]}));
  assert.equal(pack.version, 1);
  assert.equal(pack.app, 'zhenguojian');
  assert.equal(pack.count, 2);
  assert.equal(pack.dramas.length, 2);
});

test('package parsing tolerates a missing app tag and a null entry list but rejects other versions', () => {
  assert.equal(parseLibraryPackage('{"version":1,"dramas":[]}').count, 0);
  assert.equal(parseLibraryPackage('{"version":1,"dramas":null}').count, 0);
  assert.throws(() => parseLibraryPackage('{"kind":"viewer","version":1,"dramas":[]}'), /不是剧库文件/);
  assert.throws(() => parseLibraryPackage('{"version":2,"dramas":[]}'), /版本不兼容/);
  assert.throws(() => parseLibraryPackage('{"version":1,"dramas":5}'), /缺少剧集条目/);
  assert.throws(() => parseLibraryPackage(''), /内容为空/);
  assert.throws(() => parseLibraryPackage('not json'), /不是有效 JSON/);
  assert.throws(() => parseLibraryPackage('[1,2]'), /格式无效/);
});

test('package parsing enforces the shared size and entry limits', () => {
  assert.throws(() => parseLibraryPackage(JSON.stringify({version: 1, dramas: [], pad: 'x'.repeat(maxBytes)})), /超过 32 MB/);
  const oversized = {version: 1, count: maxEntries + 1, dramas: new Array(maxEntries + 1).fill({id: 'hongguo:1'})};
  assert.throws(() => parseLibraryPackage(JSON.stringify(oversized)), /条目过多/);
});

test('exported packages are named as xz archives', () => {
  assert.equal(libraryPackageFileName(new Date('2026-10-01T23:30:00Z')), '剧库-2026-10-01.xz');
});

test('xz magic separates compressed packages from legacy json files', () => {
  const xz = Uint8Array.from([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, 0x00, 0x04]);
  assert.equal(libraryPackageIsXZ(xz), true);
  assert.equal(libraryPackageIsXZ(new TextEncoder().encode('{"kind":"library"}')), false);
  assert.equal(libraryPackageIsXZ(new Uint8Array(0)), false);
  assert.equal(libraryPackageIsXZ(new Uint8Array([0xfd, 0x37, 0x7a])), false);
});

test('legacy json files are normalized before they are re-uploaded', () => {
  const normalized = JSON.parse(normalizeLibraryPackage(JSON.stringify({app: 'zhenguojian', kind: 'library', version: 1, count: 1, dramas: [{id: 'hongguo:1'}], extra: 'ignored'})));
  assert.deepEqual(normalized, {app: 'zhenguojian', kind: 'library', version: 1, count: 1, dramas: [{id: 'hongguo:1'}]});
  assert.throws(() => normalizeLibraryPackage('{"version":2,"dramas":[]}'), /版本不兼容/);
});

test('file name and import summary stay stable for the shared workflow', () => {
  assert.equal(libraryPackageFileName(new Date('2026-10-01T23:30:00Z')), '剧库-2026-10-01.xz');
  assert.equal(libraryImportSummary({imported: 12, merged: 30, total: 1712}), '导入完成：新增 12 部，补全 30 部；本地剧库共 1712 部。');
  assert.equal(libraryImportSummary({imported: 1, merged: 0, rejected: 2, denied: 3, total: 5}), '导入完成：新增 1 部，补全 0 部，跳过无效条目 2 条，跳过无权站源 3 条；本地剧库共 5 部。');
  assert.equal(libraryImportSummary({}), '导入完成：新增 0 部，补全 0 部；本地剧库共 0 部。');
});
