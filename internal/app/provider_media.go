package app

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type providerMedia struct {
	credentials *providerMediaCredentials
	URL         string
	Referer     string
	Duration    time.Duration
	Playlist    string
	HLSKey      []byte
	CENCKey     []byte
	Quality     int
	Variants    []providerMedia
}

func (d *Downloader) providerBaseURL(source string) string {
	source = canonicalProviderSource(source)
	var configured, fallback string
	switch source {
	case sourceHuangguoAI:
		configured, fallback = d.cfg.HuangguoAIURL, huangguoAIBaseURL
		if !huangguoAIIsContentRoute(configured) {
			configured = ""
		}
	case sourceHuangguoVideo:
		configured, fallback = d.cfg.HuangguoVideoURL, huangguoVideoBaseURL
	case sourceHuangdou:
		configured, fallback = d.cfg.HuangdouURL, huangdouBaseURL
	case sourceHongguo:
		configured, fallback = d.cfg.HongguoURL, hongguoBaseURL
	case sourceHuangju:
		configured, fallback = d.cfg.HuangjuURL, huangjuBaseURL
	case sourceYeguo:
		configured, fallback = d.cfg.YeguoURL, yeguoBaseURL
	case sourceDSD:
		configured, fallback = d.cfg.DSDURL, dsdBaseURL
	default:
		if isDuanjuProviderSource(source) {
			return d.duanjuBaseURL(source)
		}
		fallback = "https://d2pypzndaqisk.cloudfront.net"
	}
	return strings.TrimRight(firstNonEmpty(configured, fallback), "/")
}

func providerSourceForURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	host := strings.ToLower(parsed.Hostname())
	switch {
	case huangguoAIIsKnownHostname(host):
		return sourceHuangguoAI
	case host == "huangguo.video":
		return sourceHuangguoVideo
	case host == "tideember.cc" || host == "xqjurgek.top":
		return sourceHuangdou
	case host == "hongguoduanju.com" || host == "www.hongguoduanju.com":
		return sourceHongguo
	case host == "huangju.net" || host == "www.huangju.net" || host == "api.huangju.net" ||
		host == "yanyushorttv.cc" || host == "www.yanyushorttv.cc" || host == "api.yanyushorttv.cc" ||
		host == "yanyushorttv.top" || host == "www.yanyushorttv.top" || host == "api.yanyushorttv.top" ||
		strings.HasSuffix(host, ".yanyushorttv.cc") || strings.HasSuffix(host, ".yanyushorttv.top"):
		return sourceHuangju
	case host == "delta.ygrwdsgt.cc" || host == "ygdj7.com" || host == "www.ygdj7.com" ||
		host == "yeguodj.com" || host == "www.yeguodj.com" ||
		strings.HasSuffix(host, ".buxefaex.cc") || strings.HasSuffix(host, ".fzchosdi.cc") ||
		strings.HasSuffix(host, ".ocdjlxow.cc"):
		return sourceYeguo
	case host == "dsd.com.se" || host == "www.dsd.com.se":
		return sourceDSD
	}
	if source := duanjuSourceForHost(host); source != "" {
		return source
	}
	return ""
}

func (d *Downloader) providerURLCandidates(raw string) []string {
	source := providerSourceForURL(raw)
	if source == "" || source == sourceHuangju || source == sourceYeguo || isDuanjuProviderSource(source) {
		return []string{raw}
	}
	parsed, _ := url.Parse(raw)
	d.providerMu.Lock()
	preferred := d.providerHosts[source]
	d.providerMu.Unlock()
	var candidates []string
	seen := map[string]bool{}
	add := func(candidate string) {
		if candidate != "" && !seen[candidate] {
			seen[candidate] = true
			candidates = append(candidates, candidate)
		}
	}
	add(raw)
	add(rehostProviderURL(parsed, preferred))
	configured := d.providerBaseURL(source)
	add(rehostProviderURL(parsed, configured))
	if source == sourceHuangguoAI {
		d.providerMu.Lock()
		routes := append([]string(nil), d.huangguoAIRoutes...)
		d.providerMu.Unlock()
		for _, route := range routes {
			add(rehostProviderURL(parsed, route))
		}
	}
	if providerSourceForURL(configured) == "" {
		return candidates
	}
	for _, candidate := range providerURLCandidates(raw) {
		add(candidate)
	}
	return candidates
}

func (d *Downloader) resolveProviderMedia(ctx context.Context, task Task) (providerMedia, error) {
	chapter := task.Chapter
	chapter.Source = canonicalProviderSource(chapter.Source)
	if chapter.Source == "" {
		chapter.Source = sourceFromDramaID(task.DramaID)
	}
	switch chapter.Source {
	case sourceHuangju:
		return d.resolveHuangjuMedia(ctx, task)
	case sourceYeguo:
		return d.resolveYeguoMedia(ctx, task)
	case sourceDSD:
		return d.resolveDSDMedia(ctx, task)
	}
	if isDuanjuProviderSource(chapter.Source) {
		return d.resolveDuanjuMedia(ctx, task)
	}
	if strings.HasPrefix(chapter.VideoURL, "hongguo-cenc://") {
		return d.resolveHongguoMedia(ctx, task)
	}
	if chapter.PageURL == "" && (chapter.Source == sourceHuangguoAI || chapter.Source == sourceHuangguoVideo) {
		if source, sourceID, valid := splitProviderDramaID(task.DramaID); valid {
			_, chapters, err := d.GetHuangguoChapters(ctx, source, sourceID)
			if err != nil {
				return providerMedia{}, fmt.Errorf("刷新旧任务播放地址失败: %w", err)
			}
			matched := false
			for _, fresh := range chapters {
				if fresh.ID == chapter.ID || chapterEpisodeNumber(fresh, 0) == chapterEpisodeNumber(chapter, task.Index) {
					chapter = fresh
					matched = true
					break
				}
			}
			if !matched {
				return providerMedia{}, fmt.Errorf("原章节已变化，请更新该合集后重新下载")
			}
		}
	}
	media := providerMedia{URL: chapter.VideoURL, Referer: firstNonEmpty(chapter.Referer, d.providerBaseURL(chapter.Source)+"/")}
	if chapter.Source == sourceHuangdou {
		_, sourceID, valid := splitProviderDramaID(task.DramaID)
		if valid {
			sequence, err := strconv.Atoi(chapter.EpisodeString(task.Index))
			if err != nil || sequence < 1 {
				return providerMedia{}, fmt.Errorf("黄豆集数无效")
			}
			client := newHuangdouAPIClient(d)
			media, err = d.resolveHuangdouPlayback(ctx, client, sourceID, sequence)
			if err != nil {
				return providerMedia{}, err
			}
			media.Referer = client.host + "/home"
		}
	}
	if chapter.PageURL != "" && (chapter.Source == sourceHuangguoAI || chapter.Source == sourceHuangguoVideo) {
		requestCtx := ctx
		pageURL := chapter.PageURL
		if chapter.Source == sourceHuangguoAI {
			sourceID := ""
			if _, parsedID, ok := splitProviderDramaID(task.DramaID); ok {
				sourceID = parsedID
			}
			if sourceID == "" {
				return providerMedia{}, fmt.Errorf("黄果播放页缺少有效剧集 ID")
			}
			episode := chapter.EpisodeString(task.Index)
			base := d.huangguoAIContentBaseURL(ctx)
			pageURL = huangguoAIPlaybackPageURL(base, sourceID, episode)
			requestCtx = context.WithValue(ctx, providerTextValidatorKey{}, providerTextValidator(func(body, effectiveURL string) error {
				if err := validateHuangguoAIPlaybackPage(body, effectiveURL, sourceID, episode); err != nil {
					return err
				}
				if mediaURL := parseAIVideoURL(body, effectiveURL); !isProviderHTTPMediaURL(mediaURL) {
					return errors.New("黄果播放页未返回有效播放地址")
				}
				return nil
			}))
		}
		body, pageURL, err := d.fetchProviderTextURL(requestCtx, pageURL, media.Referer)
		if err != nil {
			return providerMedia{}, err
		}
		if chapter.Source == sourceHuangguoAI {
			media.URL = parseAIVideoURL(body, pageURL)
		} else {
			media.URL = parseDataHLS(body, pageURL)
		}
		media.Referer = pageURL
	}
	if !isProviderHTTPMediaURL(media.URL) {
		return providerMedia{}, fmt.Errorf("%s 未返回有效播放地址，请刷新章节或确认站点访问权限", chapter.Source)
	}
	parsed, _ := url.Parse(media.URL)
	if strings.HasSuffix(strings.ToLower(parsed.Path), ".m3u8") {
		selected, err := d.fetchMediaPlaylistForMedia(ctx, media)
		if err != nil {
			return providerMedia{}, fmt.Errorf("获取播放列表失败: %w", err)
		}
		media = selected
	}
	return media, nil
}
