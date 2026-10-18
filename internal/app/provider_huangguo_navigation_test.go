package app

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

const huangguoNavigationFixture = `<article class="route-card is-recommend" data-url="https://pazi.kmexvuoz.cc"><span class="url-text">pazi.kmexvuoz.cc</span></article>
<article class="route-card" data-url="https://nk8t.kmexvuoz.cc"><span class="url-text">nk8t.kmexvuoz.cc</span></article>
<a class="use-btn" href="https://huangguoai.com" rel="nofollow">旧域名</a>`

func TestHuangguoAIDiscoveryAcceptsCurrentContentFamily(t *testing.T) {
	routes := parseHuangguoAIRoutes(huangguoNavigationFixture)
	if len(routes) != 2 || routes[0] != "https://pazi.kmexvuoz.cc" || routes[1] != "https://nk8t.kmexvuoz.cc" {
		t.Fatalf("navigation routes=%v", routes)
	}
	if !huangguoAIIsContentRoute("https://pazi.kmexvuoz.cc") || huangguoAIIsContentRoute("https://huangguoai.ai") {
		t.Fatal("content family classification is wrong")
	}
	if !huangguoAIIsKnownHostname("huangguoai.ai") || !huangguoAIIsKnownHostname("pazi.kmexvuoz.cc") {
		t.Fatal("known host classification rejected a valid host")
	}
}

const huangguoRotatedNavigationFixture = `<article class="route-card is-recommend" data-url="https://ux90.rurhvbhx.cc"><span class="url-text">ux90.rurhvbhx.cc</span></article>
<article class="route-card" data-url="https://vtzi.rurhvbhx.cc"><span class="url-text">vtzi.rurhvbhx.cc</span></article>
<article class="route-card" data-url="https://jukn.rurhvbhx.cc"><span class="url-text">jukn.rurhvbhx.cc</span></article>
<a class="use-btn" href="https://huangguoai.com/compliance-2257/" rel="nofollow">合规声明</a>
<a href="https://t.me/huangguofans">频道</a>
<a href="https://www.googletagmanager.com/gtag/js">统计</a>
<img src="https://pic.wirqed.cn/cover.jpg">`

func TestHuangguoAIDiscoveryFollowsRotatedContentDomains(t *testing.T) {
	routes := parseHuangguoAIRoutes(huangguoRotatedNavigationFixture)
	if len(routes) != 3 {
		t.Fatalf("rotated navigation routes=%v", routes)
	}
	for _, route := range routes {
		if !huangguoAIIsContentRoute(route) {
			t.Fatalf("discovered rotated route was rejected: %s", route)
		}
		if !huangguoAIIsKnownHostname(huangguoAIHost(route)) {
			t.Fatalf("discovered rotated host is not usable: %s", route)
		}
	}
	for _, blocked := range []string{"https://huangguoai.ai", "https://huangguoai.com", "https://t.me", "https://www.googletagmanager.com", "https://pic.wirqed.cn"} {
		if huangguoAIIsContentRoute(blocked) {
			t.Fatalf("non content host was accepted as a content route: %s", blocked)
		}
	}
	if routes[0] != "https://ux90.rurhvbhx.cc" {
		t.Fatalf("discovery order changed: %v", routes)
	}
}

func TestHuangguoAIRotatedFamilyResolvesContentBase(t *testing.T) {
	var requested []string
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		requested = append(requested, request.URL.Hostname()+request.URL.Path)
		if request.URL.Hostname() == "huangguoai.ai" {
			return rankingHTTPResponse(request, http.StatusOK, huangguoRotatedNavigationFixture), nil
		}
		return rankingHTTPResponse(request, http.StatusOK, huangguoRotatedNavigationFixture), nil
	})
	d.cfg.HuangguoAIURL = ""
	base := d.huangguoAIContentBaseURL(context.Background())
	if !strings.HasPrefix(base, "https://ux90.rurhvbhx.cc") {
		t.Fatalf("content base %q was not resolved to the rotated content host", base)
	}
	if strings.Contains(base, "huangguoai.ai") {
		t.Fatalf("navigation page was used as the content base: %q", base)
	}
	if len(requested) == 0 || requested[0] != "huangguoai.ai/" {
		t.Fatalf("route discovery did not read the navigation page first: %v", requested)
	}
	d.cfg.HuangguoAIURL = base
	if got := d.huangguoAIContentBaseURL(context.Background()); got != base {
		t.Fatalf("explicit content route was not preserved: %q", got)
	}
}

func TestHuangguoAIChaptersUseDiscoveredRouteInsteadOfNavigationPage(t *testing.T) {
	var requested []string
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		requested = append(requested, request.URL.Hostname()+request.URL.Path)
		switch request.URL.Hostname() {
		case "huangguoai.ai":
			if request.URL.Path != "/" {
				return rankingHTTPResponse(request, http.StatusNotFound, "missing"), nil
			}
			return rankingHTTPResponse(request, http.StatusOK, huangguoNavigationFixture), nil
		case "pazi.kmexvuoz.cc":
			body := `<script id="videoInitialData" type="application/json">{"id":"1121","ep":"1","videoSrc":"https://media.example/two.mp4","epPlaySrcs":{"1":"https://media.example/one.mp4","2":"https://media.example/two.mp4"}}</script>`
			return rankingHTTPResponse(request, http.StatusOK, body), nil
		default:
			return rankingHTTPResponse(request, http.StatusBadGateway, "unexpected host"), nil
		}
	})
	title, chapters, err := d.fetchHuangguoAIChapters(context.Background(), "1121")
	if err != nil || len(chapters) != 1 || title == "" {
		t.Fatalf("chapters=%d title=%q error=%v", len(chapters), title, err)
	}
	if requested[0] != "huangguoai.ai/" || !strings.HasPrefix(requested[1], "pazi.kmexvuoz.cc/video/1121/") {
		t.Fatalf("detail request did not use the discovered content route: %v", requested)
	}
	for _, path := range requested {
		if strings.HasPrefix(path, "huangguoai.ai/video/") {
			t.Fatalf("navigation page was treated as a content route: %v", requested)
		}
	}
}

func TestHuangguoAINavigationPageIsNeverUsedAsContentBase(t *testing.T) {
	d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.Path == "/" {
			return rankingHTTPResponse(request, http.StatusOK, huangguoNavigationFixture), nil
		}
		return rankingHTTPResponse(request, http.StatusNotFound, "missing"), nil
	})
	d.providerHosts[sourceHuangguoAI] = "https://huangguoai.ai"
	d.huangguoAIRoutes = []string{"https://huangguoai.ai", "https://nk8t.kmexvuoz.cc"}
	d.huangguoAIRouteChecked = true
	if base := d.huangguoAIContentBaseURL(context.Background()); base != "https://nk8t.kmexvuoz.cc" {
		t.Fatalf("content base=%q", base)
	}
}
