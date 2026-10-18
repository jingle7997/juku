package app

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func TestParseHuangguoAIRoutesKeepsTextRoutesOnly(t *testing.T) {
	body := `<article data-url="https://alpha.hwqlgzvsk.cc"><a href="https://alpha.hwqlgzvsk.cc/ai-duanju/">线路一</a></article>
<article data-url="https://beta.hwqlgzvsk.cc">线路二</article>
<a href="https://example.com/not-a-route">外部链接</a>
<a href="https://alpha.hwqlgzvsk.cc">重复线路</a>`
	got := parseHuangguoAIRoutes(body)
	if len(got) != 2 || got[0] != "https://alpha.hwqlgzvsk.cc" || got[1] != "https://beta.hwqlgzvsk.cc" {
		t.Fatalf("routes=%v", got)
	}
}

func TestHuangguoAIPageIdentityAndEpisodeAreValidated(t *testing.T) {
	body := `<script id="videoInitialData" type="application/json">{"id":"7187","ep":"2","videoSrc":"https://media.example/default.m3u8","epPlaySrcs":{"1":"https://media.example/one.m3u8","2":"https://media.example/two.m3u8"}}</script>`
	page := "https://alpha.hwqlgzvsk.cc/video/7187/ep-2/"
	if err := validateHuangguoAIPlaybackPage(body, page, "7187", "2"); err != nil {
		t.Fatal(err)
	}
	if got := parseAIVideoURL(body, page); got != "https://media.example/two.m3u8" {
		t.Fatalf("episode 2 resolved to %q", got)
	}
	if err := validateHuangguoAIPlaybackPage(body, page, "9999", "2"); err == nil {
		t.Fatal("accepted a different drama")
	}
	if err := validateHuangguoAIPlaybackPage(body, page, "7187", "1"); err == nil {
		t.Fatal("accepted a different episode")
	}
}

func TestHuangguoAIPagePathsMapStableEpisodeKeys(t *testing.T) {
	body := `<section class="hg-web-play">
<a class="hg-web-play__ep is-active" href="/video/7187/" data-ep-id="1">01</a>
<a class="hg-web-play__ep" href="/video/7187/ep-2/" data-ep-id="2">02</a>
<a class="hg-web-play__ep" href="/video/9999/" data-ep-id="1">推荐剧</a>
</section>`
	episodes := parseHuangguoAIEpisodes(body, "https://alpha.hwqlgzvsk.cc/video/7187/", "7187")
	if len(episodes) != 2 {
		t.Fatalf("episodes=%+v", episodes)
	}
	if episodes[0].Key != "1" || episodes[0].Index != 1 || episodes[1].Key != "2" || episodes[1].Index != 2 {
		t.Fatalf("unstable episode keys: %+v", episodes)
	}
}

func TestHuangguoSortDetailIdentityAcceptsLegacyAndNewPaths(t *testing.T) {
	patch := Drama{Source: sourceHuangguoAI, SourceID: "453"}
	for _, path := range []string{
		"https://huangguoai.ai/video/453/",
		"https://huangguoai.ai/detail/453/",
		"https://alpha.hwqlgzvsk.cc/video/453/",
	} {
		actual, _ := url.Parse(path)
		if !huangguoSortDetailIdentityMatches(actual, actual, patch) {
			t.Fatalf("rejected matching path %s", path)
		}
	}
}

func TestHuangguoPlaybackRetriesNextContentRoute(t *testing.T) {
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		switch strings.ToLower(request.URL.Hostname()) {
		case "first.hwqlgzvsk.cc":
			body := `<script id="videoInitialData" type="application/json">{"id":"9999","ep":"2","videoSrc":""}</script>`
			return rankingHTTPResponse(request, http.StatusOK, body), nil
		case "second.hwqlgzvsk.cc":
			body := `<script id="videoInitialData" type="application/json">{"id":"7187","ep":"2","videoSrc":"https://media.example/episode-2.mp4"}</script>`
			return rankingHTTPResponse(request, http.StatusOK, body), nil
		default:
			return rankingHTTPResponse(request, http.StatusBadGateway, fmt.Sprintf("unexpected host %s", request.URL.Hostname())), nil
		}
	})
	d.providerHosts[sourceHuangguoAI] = "https://first.hwqlgzvsk.cc"
	d.huangguoAIRoutes = []string{"https://first.hwqlgzvsk.cc", "https://second.hwqlgzvsk.cc"}
	d.huangguoAIRouteChecked = true
	media, err := d.resolveProviderMedia(context.Background(), Task{
		DramaID: "huangguoai:7187",
		Index:   2,
		Chapter: Chapter{
			ID:             "huangguoai:7187:2",
			Source:         sourceHuangguoAI,
			PageURL:        "https://first.hwqlgzvsk.cc/video/7187/ep-2/",
			CurrentEpisode: rawEpisode(2),
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if media.URL != "https://media.example/episode-2.mp4" {
		t.Fatalf("playback resolved to %q", media.URL)
	}
}

func TestHuangguoSortDetailDiscoversContentRouteBeforeVideoPage(t *testing.T) {
	var paths []string
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		paths = append(paths, request.URL.Hostname()+request.URL.Path)
		switch request.URL.Hostname() {
		case "huangguoai.ai":
			if request.URL.Path != "/" {
				return rankingHTTPResponse(request, http.StatusNotFound, "missing"), nil
			}
			return rankingHTTPResponse(request, http.StatusOK, `<a data-url="https://route.hwqlgzvsk.cc">线路</a>`), nil
		case "route.hwqlgzvsk.cc":
			body := `<script>window.__hgSsp={"cdnDomain":"https://pic.wirqed.cn"}</script><script id="videoInitialData" type="application/json">{"id":"6139","title":"一个乖乖女","coverSrc":"/cover.png?auth_key=fixture","episodeCount":"5"}</script>`
			return rankingHTTPResponse(request, http.StatusOK, body), nil
		default:
			return rankingHTTPResponse(request, http.StatusBadGateway, "unexpected"), nil
		}
	})
	body, pageURL, err := d.fetchHuangguoSortDetailPage(context.Background(), sourceHuangguoAI, "6139")
	if err != nil {
		t.Fatal(err)
	}
	patch, err := parseHuangguoSortDetail(body, pageURL, Drama{ID: "huangguoai:6139", Source: sourceHuangguoAI, SourceID: "6139"})
	if err != nil {
		t.Fatal(err)
	}
	if bestDramaCover(patch) != "https://pic.wirqed.cn/cover.png?auth_key=fixture" || len(paths) < 2 || paths[0] != "huangguoai.ai/" || paths[1] != "route.hwqlgzvsk.cc/video/6139/" {
		t.Fatalf("detail route discovery failed: paths=%v cover=%q", paths, bestDramaCover(patch))
	}
}
