(function (root) {
  'use strict';
  const kind = 'library';
  const version = 1;
  const maxBytes = 32 * 1024 * 1024;
  const maxEntries = 200000;

  function parseLibraryPackage(text) {
    const raw = String(text == null ? '' : text).trim();
    if (!raw) throw new Error('剧库文件内容为空');
    if (raw.length > maxBytes) throw new Error('剧库文件超过 32 MB');
    let document;
    try {
      document = JSON.parse(raw);
    } catch (error) {
      throw new Error('剧库文件不是有效 JSON：' + error.message);
    }
    if (!document || typeof document !== 'object' || Array.isArray(document)) throw new Error('剧库文件格式无效');
    if (document.kind && document.kind !== kind) throw new Error('这不是剧库文件');
    if (document.version !== version) throw new Error('剧库文件版本不兼容，请使用新版程序导出');
    const dramas = document.dramas == null ? [] : document.dramas;
    if (!Array.isArray(dramas)) throw new Error('剧库文件缺少剧集条目');
    if (dramas.length > maxEntries) throw new Error('剧库文件条目过多');
    return {app: typeof document.app === 'string' ? document.app : '', version, count: dramas.length, dramas};
  }

  const xzMagic = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00];

  function libraryPackageIsXZ(payload) {
    const bytes = payload instanceof Uint8Array ? payload : new Uint8Array(payload || 0);
    if (bytes.length < xzMagic.length) return false;
    for (let index = 0; index < xzMagic.length; index += 1) if (bytes[index] !== xzMagic[index]) return false;
    return true;
  }

  function normalizeLibraryPackage(text) {
    const pack = parseLibraryPackage(text);
    return JSON.stringify({app: pack.app, kind, version, count: pack.count, dramas: pack.dramas});
  }

  function libraryPackageFileName(date) {
    const stamp = (date instanceof Date && !isNaN(date) ? date : new Date()).toISOString().substring(0, 10);
    return '剧库-' + stamp + '.xz';
  }

  function libraryImportSummary(result) {
    const value = result || {};
    const parts = ['新增 ' + (value.imported || 0) + ' 部', '补全 ' + (value.merged || 0) + ' 部'];
    if (value.rejected) parts.push('跳过无效条目 ' + value.rejected + ' 条');
    if (value.denied) parts.push('跳过无权站源 ' + value.denied + ' 条');
    return '导入完成：' + parts.join('，') + '；本地剧库共 ' + (value.total || 0) + ' 部。';
  }

  const libraryTransfer = {version, maxBytes, maxEntries, parseLibraryPackage, libraryPackageIsXZ, normalizeLibraryPackage, libraryPackageFileName, libraryImportSummary};
  if (typeof module !== 'undefined' && module.exports) module.exports = libraryTransfer;
  if (root) root.JukuLibraryTransfer = libraryTransfer;
})(typeof window !== 'undefined' ? window : null);
