package app

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func TestDuanjuRankingBoardsCoverEverySource(t *testing.T) {
	want := map[string]int{
		sourceYaguo: 2, sourceMaoguo: 1, sourceFanguo: 3, sourceGuanguo: 1,
		sourceHeguo: 3, sourceXingguo: 1, sourceHuaguo: 1, sourceNiuguo: 5,
		sourcePiguo: 3, sourceWuguo: 5,
	}
	got := map[string]int{}
	for _, board := range rankingBoards {
		if isDuanjuProviderSource(board.Source) {
			got[board.Source]++
		}
	}
	for source, count := range want {
		if got[source] != count {
			t.Fatalf("%s should expose %d ranking boards, got %d", source, count, got[source])
		}
	}
	for _, source := range duanjuProviderIDs() {
		if got[source] == 0 {
			t.Fatalf("%s has no ranking board", source)
		}
	}
}

func TestDuanjuRankingBoardCategoriesMatchTheirSource(t *testing.T) {
	for _, board := range rankingBoards {
		if !isDuanjuProviderSource(board.Source) {
			continue
		}
		if board.path == "" {
			if board.Source != sourceGuanguo {
				t.Fatalf("%s has no category", board.ID)
			}
			continue
		}
		if !duanjuValidCategory(board.Source, board.path) {
			t.Fatalf("%s uses category %q that %s does not accept", board.ID, board.path, board.Source)
		}
	}
}

func TestDuanjuRankingRoutesThroughTheSourceCatalog(t *testing.T) {
	for _, source := range []string{sourceHuaguo, sourceWuguo, sourcePiguo} {
		board, found := findDuanjuRankingBoard(source)
		if !found {
			t.Fatalf("%s has no ranking board", source)
		}
		requested := ""
		d, server := duanjuFixtureDownloader(t, func(writer http.ResponseWriter, request *http.Request) {
			requested = request.URL.RequestURI()
			writer.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = writer.Write([]byte(duanjuRankingFixture(source)))
		})
		d.providerHosts[source] = server.URL
		page, err := d.fetchRankingPage(context.Background(), board, 1)
		if err != nil {
			t.Fatalf("%s failed: %v", board.ID, err)
		}
		if !duanjuRankingRequestMatches(board, requested) {
			t.Fatalf("%s did not request its category %q: %s", board.ID, board.path, requested)
		}
		if len(page.Items) == 0 {
			t.Fatalf("%s returned no items", board.ID)
		}
		for _, item := range page.Items {
			if item.Drama.ID == "" || item.Drama.Source != source {
				t.Fatalf("%s returned a foreign item: %+v", board.ID, item.Drama)
			}
			if item.Drama.Cover != nil || item.Drama.CoverURL != nil || item.Drama.Pic != nil {
				t.Fatalf("%s must not expose source images", board.ID)
			}
		}
		if page.Items[0].Rank != 1 {
			t.Fatalf("%s did not rank the first item: %+v", board.ID, page.Items[0])
		}
	}
}

func duanjuRankingRequestMatches(board rankingBoard, requested string) bool {
	if board.path == "" {
		return true
	}
	for _, form := range []string{board.path, url.QueryEscape(board.path), url.PathEscape(board.path)} {
		if strings.Contains(requested, form) {
			return true
		}
	}
	return false
}

func findDuanjuRankingBoard(source string) (rankingBoard, bool) {
	for _, board := range rankingBoards {
		if board.Source == source {
			return board, true
		}
	}
	return rankingBoard{}, false
}

func duanjuValidCategory(source, category string) bool {
	if static, found := duanjuStaticCategories[source]; found {
		for _, entry := range static {
			if entry.ID == category {
				return true
			}
		}
		return false
	}
	switch source {
	case sourceYaguo:
		return category == "9" || webProviderNumericID.MatchString(category)
	case sourceMaoguo:
		return true
	case sourceFanguo, sourceGuanguo:
		return true
	}
	return true
}

func TestDuanjuRankingBoardIdentifiersAreUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, board := range rankingBoards {
		if seen[board.ID] {
			t.Fatalf("duplicate ranking board id %q", board.ID)
		}
		seen[board.ID] = true
		if board.ID == "" || board.Source == "" || board.Name == "" {
			t.Fatalf("incomplete ranking board %+v", board)
		}
	}
}

func TestDuanjuRankingRejectsUnsupportedPage(t *testing.T) {
	board, found := findRankingBoard("niuguo-drama")
	if !found {
		t.Fatal("niuguo-drama board is missing")
	}
	if singlePageRankingBoard(board) {
		t.Fatal("duanju boards should follow the source pagination")
	}
}

func duanjuRankingFixture(source string) string {
	switch source {
	case sourceYaguo:
		return `{"code":"ok","data":{"list":[{"type":"Theater","theater":{"id":1001,"title":"芽果剧","total":2}}]}}`
	case sourceMaoguo:
		return `{"data":{"list":[{"id":"2001","title":"猫果剧","total":5}]}}`
	case sourceFanguo:
		return `{"result":{"elements":[{"contents":[{"duanjuVo":{"duanjuId":"3001","title":"饭果剧","total":4}}]}]}}`
	case sourceGuanguo:
		return `{"data":[{"oneId":"4001","title":"观果剧","episodeCount":6}]}`
	case sourceHeguo:
		return `<html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"page":1,"pages":2,"bookList":[{"bookId":"5001","bookName":"河果剧","totalChapterNum":3}]}}}</script></body></html>`
	case sourceXingguo:
		return `{"data":{"datalist":[{"id":"6001","name":"星果剧","chapterCount":3,"heat":12}]}}`
	default:
		return `<html><body><div class="module-item"><a href="/detail/9001.html" title="网页剧"><span class="pic-text">第2集</span></a></div></body></html>`
	}
}

func duanjuProviderIDs() []string {
	ids := make([]string, 0, len(duanjuProviderCatalog))
	for _, spec := range duanjuProviderCatalog {
		ids = append(ids, spec.ID)
	}
	return ids
}

var _ = url.Values{}
