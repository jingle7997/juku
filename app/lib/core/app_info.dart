/// 应用元信息。
///
/// 版本号同时存在于 `pubspec.yaml` 的 `version:`，改版本时两处要一起改。
/// 之所以不引 `package_info_plus`：只为在「我的」页显示一行版本号，
/// 不值得给 iOS 构建多一个 pod 依赖。
const String kAppName = '果果短剧';
const String kAppVersion = '0.1.0';
const String kAppBuild = '1';
