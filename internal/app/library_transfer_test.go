package app

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

func libraryTransferFixture(t *testing.T) (*UIApp, *accountTestBrowser) {
	t.Helper()
	app, admin := administratorFixture(t)
	app.metadataClosed = true
	app.mu.Lock()
	app.dramas = []Drama{
		{ID: "hongguo:7000000000000000001", Source: sourceHongguo, Title: "红果样本", TotalEpisode: 3, CoverURL: "https://hongguo.example.test/a.jpg", Heat: "本地热度", Views: "本地播放量", OnlineDate: "2026-01-02", ReleaseStatus: "finished", Tags: []string{"都市"}},
		{ID: "huangdou:6a8c4435817f7dacc5972d57", Source: sourceHuangdou, Title: "黄豆样本", CategoryName: "现代都市", Heat: "12万热度"},
	}
	app.librarySources = map[string]librarySourceState{
		sourceHongguo:  {Status: "ready", Count: 1, UpdatedAt: time.Now()},
		sourceHuangdou: {Status: "ready", Count: 1, UpdatedAt: time.Now()},
	}
	app.libraryAttempted = true
	app.mu.Unlock()
	return app, admin
}

func TestLibraryExportWritesTheSharedExchangeFormat(t *testing.T) {
	app, admin := libraryTransferFixture(t)
	result := admin.request(t, http.MethodGet, "/api/ui/admin/library", nil)
	viewerResultOK(t, result)
	if media := result.Header().Get("Content-Type"); media != "application/x-xz" {
		t.Fatalf("export should be an xz stream, got %q", media)
	}
	disposition := result.Header().Get("Content-Disposition")
	if !strings.Contains(disposition, `.xz"`) || !strings.Contains(disposition, `filename*=UTF-8''`) {
		t.Fatalf("export should be named as an xz file with a UTF-8 name, got %q", disposition)
	}
	payload, err := libraryExchangeDecompress(result.Body.Bytes())
	if err != nil {
		t.Fatalf("export is not a valid xz stream: %v", err)
	}
	var document libraryExchange
	if json.Unmarshal(payload, &document) != nil {
		t.Fatal(string(payload))
	}
	if document.App != libraryExchangeApp || document.Kind != libraryExchangeKind || document.Version != libraryExchangeVersion || document.Count != 2 {
		t.Fatal("incorrect exchange header", string(payload))
	}
	if document.ExportedAt.IsZero() {
		t.Fatal("missing export time")
	}
	byID := map[string]libraryExchangeDrama{}
	for _, entry := range document.Dramas {
		byID[entry.ID] = entry
	}
	hongguo := byID["hongguo:7000000000000000001"]
	if hongguo.Source != sourceHongguo || hongguo.SourceID != "7000000000000000001" || hongguo.Title != "红果样本" || hongguo.Episodes != 3 {
		t.Fatal("incorrect red fruit entry", hongguo)
	}
	if hongguo.Cover != "https://hongguo.example.test/a.jpg" {
		t.Fatal("cover should stay a plain source URL", hongguo.Cover)
	}
	huangdou := byID["huangdou:6a8c4435817f7dacc5972d57"]
	if huangdou.Category != "现代都市" || huangdou.Heat != "12万热度" {
		t.Fatal("incorrect yellow bean entry", huangdou)
	}
	_ = app
}

func TestLibraryImportMergesAndCompletesWithoutDeletingLocalEntries(t *testing.T) {
	app, admin := libraryTransferFixture(t)
	document := libraryExchange{
		App: "zhenguojian", Kind: libraryExchangeKind, Version: libraryExchangeVersion, ExportedAt: time.Now().UTC(),
		Dramas: []libraryExchangeDrama{
			{ID: "hongguo:7000000000000000001", Source: sourceHongguo, SourceID: "7000000000000000001", Title: "红果样本", Description: "来自真果鉴的简介", Cover: "https://hongguo.example.test/b.jpg", Episodes: 24, Category: "古装仙侠", Tags: []string{"都市"}},
			{ID: "yaguo:494853072879618", Source: sourceYaguo, SourceID: "494853072879618", Title: "芽果样本", Description: "新条目", Episodes: 30, Category: "逆袭", OnlineDate: "2026-09-01"},
			{ID: "", Title: "缺少 ID"},
			{ID: "not-a-provider-id", Title: "无法识别的 ID"},
			{ID: "hongguo:不是数字", Title: "红果 ID 非数字"},
		},
	}
	body, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	result := admin.request(t, http.MethodPost, "/api/ui/admin/library", json.RawMessage(body))
	viewerResultOK(t, result)
	var summary libraryImportResult
	if json.Unmarshal(result.Body.Bytes(), &summary) != nil {
		t.Fatal(result.Body.String())
	}
	if summary.Imported != 1 || summary.Merged != 1 || summary.Rejected != 3 || summary.Total != 3 {
		t.Fatal("incorrect import summary", result.Body.String())
	}
	app.mu.Lock()
	defer app.mu.Unlock()
	if len(app.dramas) != 3 {
		t.Fatal("local entries were lost", app.dramas)
	}
	byID := map[string]Drama{}
	for _, drama := range app.dramas {
		byID[drama.ID] = drama
	}
	hongguo := byID["hongguo:7000000000000000001"]
	if hongguo.Title != "红果样本" || hongguo.Intro != "来自真果鉴的简介" || hongguo.CategoryName != "古装仙侠" || followingEpisodeCount(hongguo) != 3 {
		t.Fatal("existing entry was not completed without overwriting local values", hongguo)
	}
	if !strings.Contains(bestDramaCover(hongguo), "a.jpg") || strings.Contains(bestDramaCover(hongguo), "b.jpg") {
		t.Fatal("existing local cover was replaced", bestDramaCover(hongguo))
	}
	if hongguo.Heat != "本地热度" || hongguo.Views != "本地播放量" || hongguo.OnlineDate != "2026-01-02" || hongguo.ReleaseStatus != "finished" {
		t.Fatal("fields the local entry already had were overwritten", hongguo.Heat, hongguo.Views, hongguo.OnlineDate, hongguo.ReleaseStatus)
	}
	yaguo := byID["yaguo:494853072879618"]
	if yaguo.Source != sourceYaguo || yaguo.OnlineDate != "2026-09-01" || followingEpisodeCount(yaguo) != 30 {
		t.Fatal("new entry was not registered", yaguo)
	}
	if app.librarySources[sourceYaguo].Count != 1 || app.librarySources[sourceHongguo].Count != 1 || app.librarySources[sourceHuangdou].Count != 1 {
		t.Fatal("source counters were not refreshed", app.librarySources)
	}
}

func TestLibraryImportIsRepeatableAndRejectsForeignVersions(t *testing.T) {
	app, admin := libraryTransferFixture(t)
	document := libraryExchange{Kind: libraryExchangeKind, Version: libraryExchangeVersion, Dramas: []libraryExchangeDrama{{ID: "yaguo:494853072879618", Title: "芽果样本", Episodes: 30}}}
	body, _ := json.Marshal(document)
	for round := 0; round < 2; round++ {
		viewerResultOK(t, admin.request(t, http.MethodPost, "/api/ui/admin/library", json.RawMessage(body)))
	}
	app.mu.Lock()
	total := len(app.dramas)
	app.mu.Unlock()
	if total != 3 {
		t.Fatal("repeated import duplicated entries", total)
	}
	second := admin.request(t, http.MethodPost, "/api/ui/admin/library", json.RawMessage(body))
	var summary libraryImportResult
	if json.Unmarshal(second.Body.Bytes(), &summary) != nil || summary.Imported != 0 || summary.Merged != 0 {
		t.Fatal("second import changed existing entries", second.Body.String())
	}
	broken := libraryExchange{Kind: libraryExchangeKind, Version: libraryExchangeVersion + 1, Dramas: []libraryExchangeDrama{{ID: "yaguo:494853072879618"}}}
	raw, _ := json.Marshal(broken)
	if result := admin.request(t, http.MethodPost, "/api/ui/admin/library", json.RawMessage(raw)); result.Code != http.StatusBadRequest || !strings.Contains(result.Body.String(), "版本不兼容") {
		t.Fatal("incompatible version was accepted", result.Code, result.Body.String())
	}
	if result := admin.request(t, http.MethodPost, "/api/ui/admin/library", "not json"); result.Code != http.StatusBadRequest {
		t.Fatal("invalid body was accepted", result.Code, result.Body.String())
	}
}

func TestLibraryTransferRequiresAnAdministrator(t *testing.T) {
	app, admin := libraryTransferFixture(t)
	member := newAccountTestBrowser(t, app)
	member.register(t, "library-member")
	for _, method := range []string{http.MethodGet, http.MethodPost} {
		result := member.request(t, method, "/api/ui/admin/library", map[string]any{})
		if result.Code != http.StatusForbidden || !strings.Contains(result.Body.String(), "admin_required") {
			t.Fatal("non administrator reached the library transfer endpoint", method, result.Code, result.Body.String())
		}
	}
	if result := admin.request(t, http.MethodDelete, "/api/ui/admin/library", nil); result.Code != http.StatusMethodNotAllowed {
		t.Fatal("unsupported method was accepted", result.Code)
	}
}
