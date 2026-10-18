package app

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
)

func TestHuangdouCoverClickUsesMatchingDetail(t *testing.T) {
	for _, matched := range []bool{true, false} {
		t.Run(fmt.Sprint(matched), func(t *testing.T) {
			d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
				if request.URL.Path != "/api/drama/detail" {
					t.Error("cover lookup requested something other than textual details", request.URL.Path)
				}
				id := "rp_target"
				if !matched {
					id = "other"
				}
				return rankingHTTPResponse(request, 200, fmt.Sprintf(`{"data":{"id":%q,"name":"虚构样本","img_y":"https://tideember.cc/synthetic-cover"}}`, id)), nil
			})
			address, err := d.fetchDramaCoverAddress(context.Background(), Drama{ID: "huangdou:target", Source: sourceHuangdou})
			if matched && (err != nil || address != "https://tideember.cc/synthetic-cover") || !matched && (err == nil || address != "") {
				t.Fatal("cover did not belong to the requested drama", address, err)
			}
		})
	}
}

func TestHuangguoCoverClickUsesScopedPageMetadata(t *testing.T) {
	for _, test := range []struct {
		name, metadata, extra, want string
		invalid                     bool
	}{
		{"image object", `"image":{"url":"/synthetic-cover?fixture=1"}`, "", "https://route.hwqlgzvsk.cc/synthetic-cover?fixture=1", false},
		{"thumbnail list", `"thumbnailUrl":["javascript:invalid","/synthetic-thumbnail"]`, "", "https://route.hwqlgzvsk.cc/synthetic-thumbnail", false},
		{"alternate CDN", `"image":"https://pic.tuafjz.cn/upload/synthetic.jpg?auth_key=fixture-0-0-test"`, "", "https://pic.tuafjz.cn/upload/synthetic.jpg?auth_key=fixture-0-0-test", false},
		{"open graph", `"image":""`, `<meta content="/synthetic-og?x=1&amp;y=2" property="og:image">`, "https://route.hwqlgzvsk.cc/synthetic-og?x=1&y=2", false},
		{"new CDN", `"image":"https://new-covers.example.org/cover"`, "", "https://new-covers.example.org/cover", false},
		{"reserved domain", `"image":"https://example.invalid/cover"`, "", "", false},
		{"no cover", `"image":""`, "", "", false},
		{"another drama", `"image":"/synthetic-cover"`, "", "", true},
	} {
		t.Run(test.name, func(t *testing.T) {
			d := rankingTestDownloader(t, func(request *http.Request) (*http.Response, error) {
				if request.URL.Hostname() == "huangguoai.ai" && request.URL.Path == "/" {
					return rankingHTTPResponse(request, http.StatusOK, `<a data-url="https://route.hwqlgzvsk.cc">线路</a>`), nil
				}
				if request.URL.Path != "/video/501/" {
					t.Error("only textual detail pages should be requested", request.URL.Path)
				}
				id := "501"
				if test.invalid {
					id = "502"
				}
				body := fmt.Sprintf(`<script type="application/ld+json">{"@graph":[{"@type":"TVSeries","url":"https://huangguoai.ai/detail/%s/","name":"合成文字",%s},{"@type":"TVSeries","url":"https://huangguoai.ai/detail/999/","name":"不得使用相关推荐","image":"/unrelated"}]}</script>`, id, test.metadata) + test.extra
				return rankingHTTPResponse(request, 200, body), nil
			})
			address, err := d.fetchDramaCoverAddress(context.Background(), Drama{ID: "huangguoai:501", Source: sourceHuangguoAI})
			want := test.want
			if address != want || (err != nil) != test.invalid {
				t.Fatal("wrong scoped cover address", address, err)
			}
		})
	}
	page := `<script type="application/ld+json">{"@type":"TVSeries","url":"https://example.invalid/detail/501/","name":"其他站点","image":"https://huangguoai.ai/unrelated"}</script><meta property="og:image" content="/unrelated">`
	if patch, err := parseHuangguoSortDetail(page, "https://huangguoai.ai/detail/501/", Drama{Source: sourceHuangguoAI, SourceID: "501"}); err == nil || bestDramaCover(patch) != "" {
		t.Fatal("accepted another site's identity")
	}
	video := strings.ReplaceAll(page, "https://example.invalid/detail/501/", "https://huangguo.video/series/501")
	if patch, err := parseHuangguoSortDetail(video, "https://huangguo.video/series/501", Drama{Source: sourceHuangguoVideo, SourceID: "series/501"}); err != nil || bestDramaCover(patch) == "" {
		t.Fatal("video source did not retain its matching cover address", err)
	}
	mirror := strings.ReplaceAll(page, "https://example.invalid/detail/501/", "https://thu.ediayikma.cc/detail/501/")
	if patch, err := parseHuangguoSortDetail(mirror, "https://huangguoai.ai/detail/501/", Drama{Source: sourceHuangguoAI, SourceID: "501"}); err != nil || bestDramaCover(patch) == "" {
		t.Fatal("known mirror lost its matching cover address", err)
	}
}

func TestHuangguoCoverUsesCurrentPageArtworkWithoutCDNRewrite(t *testing.T) {
	page := `<script>window.__hgSsp={"cdnDomain":"https://cdn-rotating.net"}</script><script id="videoInitialData" type="application/json">{"id":"6139","title":"一个乖乖女","coverSrc":"/cover-6139.jpg?sig=fixture","posterSrc":"https://other-cdn.net/poster-6139.jpg?sig=fixture","episodeCount":"5"}</script>`
	patch, err := parseHuangguoSortDetail(page, "https://ujvhqo.hwqlgzvsk.cc/video/6139/", Drama{ID: "huangguoai:6139", Source: sourceHuangguoAI, SourceID: "6139"})
	if err != nil {
		t.Fatal(err)
	}
	if got := bestDramaCover(patch); got != "https://cdn-rotating.net/cover-6139.jpg?sig=fixture" {
		t.Fatalf("page artwork was not retained: %q", got)
	}
	if fmt.Sprint(patch.TotalEpisode) != "5" || fmt.Sprint(patch.EpisodeCount) != "5" {
		t.Fatalf("page episode count was not retained: %v/%v", patch.TotalEpisode, patch.EpisodeCount)
	}
	for _, raw := range []string{
		"https://expose.eisees.com/legacy-cover.jpg?sig=fixture",
		"https://pic.wirqed.cn/current-cover.jpg?sig=fixture",
	} {
		got, ok := buildImageURL(raw)
		if !ok || got != raw {
			t.Fatalf("cover URL was rewritten: %q -> %q", raw, got)
		}
	}
}

func TestHuangguoCurrentPlayerArtworkWinsOverStaleJSONLD(t *testing.T) {
	page := `<script>window.__hgSsp={"cdnDomain":"https://pic.wirqed.cn"}</script>
<script type="application/ld+json">{"@graph":[{"@type":"WebPage","url":"https://ujvhqo.hwqlgzvsk.cc/video/6139/","name":"一个乖乖女","image":"https://expose.eisees.com/legacy.png?auth=old"},{"@type":"VideoObject","url":"https://ujvhqo.hwqlgzvsk.cc/video/6139/","name":"一个乖乖女 第1集","thumbnailUrl":["https://expose.eisees.com/legacy.png?auth=old"]}]}</script>
<body data-history="{&#34;id&#34;:&#34;6139&#34;,&#34;title&#34;:&#34;一个乖乖女&#34;,&#34;cover&#34;:&#34;/upload_01/xiao/old.png&#34;,&#34;total&#34;:&#34;5&#34;}">
<script id="videoInitialData" type="application/json">{"id":"6139","title":"一个乖乖女","coverSrc":"https://pic.wirqed.cn/upload_01/xiao/current.png?auth_key=fixture","posterSrc":"https://pic.wirqed.cn/upload_01/xiao/current.png?auth_key=fixture","episodeCount":"5"}</script>`
	patch, err := parseHuangguoSortDetail(page, "https://ujvhqo.hwqlgzvsk.cc/video/6139/", Drama{ID: "huangguoai:6139", Source: sourceHuangguoAI, SourceID: "6139"})
	if err != nil {
		t.Fatal(err)
	}
	if patch.Title != "一个乖乖女" || patch.Name != "一个乖乖女" {
		t.Fatalf("stale episode title replaced current title: %q/%q", patch.Title, patch.Name)
	}
	if got := bestDramaCover(patch); got != "https://pic.wirqed.cn/upload_01/xiao/current.png?auth_key=fixture" {
		t.Fatalf("stale JSON-LD cover replaced current player cover: %q", got)
	}
}
