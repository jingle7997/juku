package app

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func TestLiveHuangguo6139CoverAndPlaybackProbe(t *testing.T) {
	if os.Getenv("JUKU_LIVE_HUANGGUO_6139") != "1" {
		t.Skip("set JUKU_LIVE_HUANGGUO_6139=1 for text metadata and first-media playback verification")
	}
	cfg := defaultConfig()
	cfg.dataDir, cfg.OutputDir, cfg.ProxyURL, cfg.Retries = t.TempDir(), t.TempDir(), firstNonEmpty(os.Getenv("JUKU_HUANGGUO_PROXY"), "direct"), 1
	d := NewDownloader(cfg)
	defer d.client.CloseIdleConnections()
	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
	defer cancel()
	body, pageURL, err := d.fetchHuangguoSortDetailPage(ctx, sourceHuangguoAI, "6139")
	if err != nil {
		t.Fatal(err)
	}
	patch, err := parseHuangguoSortDetail(body, pageURL, Drama{ID: "huangguoai:6139", Source: sourceHuangguoAI, SourceID: "6139"})
	if err != nil {
		t.Fatal(err)
	}
	coverHost := ""
	if parsed, err := url.Parse(bestDramaCover(patch)); err == nil {
		coverHost = parsed.Hostname()
	}
	if patch.Title != "一个乖乖女" || patch.Name != "一个乖乖女" || coverHost != "pic.wirqed.cn" || !strings.Contains(strings.TrimSpace(body), "videoInitialData") || strings.TrimSpace(firstNonEmpty(fmt.Sprint(patch.TotalEpisode), fmt.Sprint(patch.EpisodeCount))) != "5" {
		t.Fatalf("unexpected live metadata: title=%q name=%q coverHost=%q total=%v episode=%v page=%s", patch.Title, patch.Name, coverHost, patch.TotalEpisode, patch.EpisodeCount, pageURL)
	}
	title, chapters, err := d.GetHuangguoChapters(ctx, sourceHuangguoAI, "6139")
	if err != nil {
		t.Fatal(err)
	}
	if title != "一个乖乖女" || len(chapters) != 5 || chapters[0].PageURL == "" || chapters[1].PageURL == "" || chapters[0].PageURL == chapters[1].PageURL || chapters[0].ID == chapters[1].ID {
		t.Fatalf("unexpected chapters: title=%q count=%d", title, len(chapters))
	}
	media, err := d.resolveProviderMedia(ctx, Task{DramaID: "huangguoai:6139", Chapter: chapters[0], Index: 1})
	if err != nil {
		t.Fatal(err)
	}
	proxy, err := d.newHLSProxy(ctx, media, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	playlist := readLiveHLSAsset(t, proxy.client, proxy.root, 4096)
	key := hlsURIAttribute.FindStringSubmatch(playlist)
	if len(key) != 2 {
		t.Fatalf("playlist missing key: %s", truncate(playlist, 300))
	}
	keyBody := readLiveHLSAsset(t, proxy.client, key[1], 64)
	if len(keyBody) != 16 {
		t.Fatalf("unexpected key length: %d", len(keyBody))
	}
	segment := ""
	for _, line := range strings.Split(playlist, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && !strings.HasPrefix(line, "#") {
			segment = line
			break
		}
	}
	if segment == "" {
		t.Fatal("playlist missing first segment")
	}
	segmentBody := readLiveHLSAsset(t, proxy.client, segment, 188)
	if len(segmentBody) == 0 {
		t.Fatal("first segment returned no bytes")
	}
	t.Logf("6139 metadata title=%q coverHost=%s chapters=%d playlist=%d key=%d segmentProbe=%d", patch.Title, coverHost, len(chapters), len(playlist), len(keyBody), len(segmentBody))
}

func readLiveHLSAsset(t *testing.T, client *http.Client, raw string, limit int64) string {
	t.Helper()
	request, err := http.NewRequest(http.MethodGet, raw, nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		t.Fatalf("asset HTTP %d for %s", response.StatusCode, request.URL.Path)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, limit))
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}
