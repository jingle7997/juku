package app

import (
	"context"
	"encoding/json"
	"io"
	"mime"
	"net/http"
	"net/url"
	"reflect"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	libraryExchangeApp     = "juku"
	libraryExchangeKind    = "library"
	libraryExchangeVersion = 1
	libraryExchangeBytes   = 32 << 20
	libraryExchangeEntries = 200000
	libraryExchangeTagMax  = 64
)

type libraryExchangeDrama struct {
	ID            string   `json:"id"`
	Source        string   `json:"source,omitempty"`
	SourceID      string   `json:"sourceId,omitempty"`
	Title         string   `json:"title,omitempty"`
	Description   string   `json:"description,omitempty"`
	Cover         string   `json:"cover,omitempty"`
	Episodes      int      `json:"episodes,omitempty"`
	Category      string   `json:"category,omitempty"`
	VIP           *bool    `json:"vip,omitempty"`
	Heat          string   `json:"heat,omitempty"`
	Views         string   `json:"views,omitempty"`
	OnlineDate    string   `json:"onlineDate,omitempty"`
	Tags          []string `json:"tags,omitempty"`
	ReleaseStatus string   `json:"releaseStatus,omitempty"`
}

type libraryExchange struct {
	App        string                 `json:"app,omitempty"`
	Kind       string                 `json:"kind"`
	Version    int                    `json:"version"`
	ExportedAt time.Time              `json:"exportedAt"`
	Count      int                    `json:"count"`
	Dramas     []libraryExchangeDrama `json:"dramas"`
}

type libraryImportResult struct {
	Imported int            `json:"imported"`
	Merged   int            `json:"merged"`
	Rejected int            `json:"rejected"`
	Denied   int            `json:"denied"`
	Total    int            `json:"total"`
	Sources  map[string]int `json:"sources"`
}

func validLibraryExchangeID(id string) bool {
	id = strings.TrimSpace(id)
	if id == "" || len(id) > 512 || strings.ContainsAny(id, ",\t\n\r") {
		return false
	}
	source, sourceID, valid := splitProviderDramaID(id)
	if !valid || len(sourceID) > 512 {
		return false
	}
	if source == sourceHongguo {
		return hongguoNumericID.MatchString(sourceID)
	}
	return true
}

func libraryExchangeText(value string, limit int) string {
	value = strings.ToValidUTF8(strings.TrimSpace(value), "")
	if len(value) > limit {
		value = value[:limit]
		for !utf8.ValidString(value) {
			value = value[:len(value)-1]
		}
	}
	return value
}

func libraryExchangeTags(values []string) []string {
	var tags []string
	seen := map[string]bool{}
	for _, value := range values {
		value = libraryExchangeText(value, 128)
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		tags = append(tags, value)
		if len(tags) >= libraryExchangeTagMax {
			break
		}
	}
	return tags
}

func libraryExchangeDramaFromDrama(drama Drama) (libraryExchangeDrama, bool) {
	source, sourceID, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return libraryExchangeDrama{}, false
	}
	entry := libraryExchangeDrama{
		ID:            providerDramaID(source, sourceID),
		Source:        source,
		SourceID:      sourceID,
		Title:         libraryExchangeText(drama.DisplayTitle(), 4096),
		Description:   libraryExchangeText(firstNonEmpty(drama.Intro, drama.Desc), 20000),
		Cover:         libraryExchangeText(bestDramaCover(drama), 4096),
		Episodes:      followingEpisodeCount(drama),
		Category:      libraryExchangeText(firstNonEmpty(drama.CategoryName, drama.CategoryNameSnake, drama.Category, drama.TypeName, drama.SortName), 512),
		Heat:          libraryExchangeText(drama.Heat, 256),
		Views:         libraryExchangeText(drama.Views, 256),
		OnlineDate:    libraryExchangeText(drama.OnlineDate, 256),
		Tags:          libraryExchangeTags(drama.Tags),
		ReleaseStatus: libraryExchangeText(drama.ReleaseStatus, 64),
	}
	if drama.VIP != nil {
		value := *drama.VIP
		entry.VIP = &value
	}
	return entry, true
}

func libraryExchangeDramaToDrama(entry libraryExchangeDrama) (Drama, bool) {
	id := strings.TrimSpace(entry.ID)
	if !validLibraryExchangeID(id) {
		return Drama{}, false
	}
	source, sourceID, _ := splitProviderDramaID(id)
	id = providerDramaID(source, sourceID)
	title := libraryExchangeText(entry.Title, 4096)
	description := libraryExchangeText(entry.Description, 20000)
	drama := Drama{
		ID:            id,
		Source:        source,
		SourceID:      sourceID,
		Title:         title,
		Name:          title,
		Intro:         description,
		Desc:          description,
		Cover:         libraryExchangeText(entry.Cover, 4096),
		CategoryName:  libraryExchangeText(entry.Category, 512),
		Heat:          libraryExchangeText(entry.Heat, 256),
		Views:         normalizeViews(libraryExchangeText(entry.Views, 256)),
		OnlineDate:    normalizeDate(libraryExchangeText(entry.OnlineDate, 256)),
		Tags:          libraryExchangeTags(entry.Tags),
		ReleaseStatus: libraryExchangeText(entry.ReleaseStatus, 64),
	}
	if entry.Episodes > 0 && entry.Episodes <= 100000 {
		drama.TotalEpisode = entry.Episodes
		drama.EpisodeCount = entry.Episodes
	}
	if entry.VIP != nil {
		value := *entry.VIP
		drama.VIP = &value
	}
	return drama, true
}

func (app *UIApp) libraryExchangePackage(ctx context.Context) libraryExchange {
	app.mu.Lock()
	dramas := append([]Drama{}, app.dramas...)
	app.mu.Unlock()
	document := libraryExchange{App: libraryExchangeApp, Kind: libraryExchangeKind, Version: libraryExchangeVersion, ExportedAt: time.Now().UTC().Truncate(time.Second), Dramas: []libraryExchangeDrama{}}
	seen := map[string]bool{}
	for _, drama := range dramas {
		if !dramaAllowed(ctx, drama.ID, drama.Source) {
			continue
		}
		entry, valid := libraryExchangeDramaFromDrama(drama)
		if !valid || seen[entry.ID] {
			continue
		}
		seen[entry.ID] = true
		document.Dramas = append(document.Dramas, entry)
	}
	document.Count = len(document.Dramas)
	return document
}

func (app *UIApp) handleLibraryTransfer(writer http.ResponseWriter, request *http.Request) {
	switch request.Method {
	case http.MethodGet:
		app.handleLibraryExport(writer, request)
	case http.MethodPost:
		app.handleLibraryImport(writer, request)
	default:
		writer.Header().Set("Allow", "GET, POST")
		writeJSON(writer, http.StatusMethodNotAllowed, map[string]string{"error": "请求方法不支持"})
	}
}

func (app *UIApp) handleLibraryExport(writer http.ResponseWriter, request *http.Request) {
	if !playbackRequestAllowed(writer, request, http.MethodGet) {
		return
	}
	document := app.libraryExchangePackage(request.Context())
	payload, err := json.Marshal(document)
	if err != nil {
		writeJSON(writer, http.StatusInternalServerError, map[string]string{"error": "剧库导出失败：" + publicError(err).Error()})
		return
	}
	compressed, err := libraryExchangeCompress(payload)
	if err != nil {
		writeJSON(writer, http.StatusInternalServerError, map[string]string{"error": "剧库导出失败：" + publicError(err).Error()})
		return
	}
	writer.Header().Set("Content-Type", "application/x-xz")
	fileName := libraryExchangeFileName(time.Now())
	writer.Header().Set("Content-Disposition", "attachment; filename=\""+libraryExchangeASCIIName(time.Now())+"\"; filename*=UTF-8''"+url.PathEscape(fileName))
	writer.Header().Set("X-Juku-Library-Count", strconv.Itoa(document.Count))
	writer.Header().Set("Content-Length", strconv.Itoa(len(compressed)))
	writer.WriteHeader(http.StatusOK)
	_, _ = writer.Write(compressed)
}

func libraryExchangeFileName(now time.Time) string {
	return "剧库-" + now.Format("2006-01-02") + ".xz"
}

func libraryExchangeASCIIName(now time.Time) string {
	return "juku-library-" + now.Format("2006-01-02") + ".xz"
}

func (app *UIApp) handleLibraryImport(writer http.ResponseWriter, request *http.Request) {
	if !playbackRequestAllowed(writer, request, http.MethodPost) {
		return
	}
	contentType, _, _ := mime.ParseMediaType(request.Header.Get("Content-Type"))
	switch contentType {
	case "application/x-xz", "application/octet-stream", "application/json", "":
	default:
		writeJSON(writer, http.StatusUnsupportedMediaType, map[string]string{"error": "剧库文件必须使用 XZ 或 JSON"})
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(writer, request.Body, libraryExchangeBytes))
	if err != nil {
		writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件读取失败或超过 32 MB"})
		return
	}
	payload := body
	switch {
	case libraryExchangeIsXZ(body) || contentType == "application/x-xz":
		payload, err = libraryExchangeDecompress(body)
		if err != nil {
			writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件解压失败，请确认是有效的 XZ 压缩包"})
			return
		}
	case contentType == "application/json":
	default:
		writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件格式无效"})
		return
	}
	var document libraryExchange
	if json.Unmarshal(payload, &document) != nil {
		writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件格式无效"})
		return
	}
	if document.Version != libraryExchangeVersion {
		writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件版本不兼容"})
		return
	}
	if len(document.Dramas) > libraryExchangeEntries {
		writeJSON(writer, http.StatusBadRequest, map[string]string{"error": "剧库文件条目过多"})
		return
	}
	result, err := app.importLibraryExchange(request.Context(), document)
	if err != nil {
		writeJSON(writer, http.StatusInternalServerError, map[string]string{"error": "剧库导入失败：" + publicError(err).Error()})
		return
	}
	writeJSON(writer, http.StatusOK, result)
}

func libraryExchangeClearCovered(local libraryExchangeDrama, drama Drama) Drama {
	if local.Description != "" {
		drama.Intro, drama.Desc = "", ""
	}
	if local.Cover != "" {
		drama.Cover, drama.CoverURL = nil, nil
	}
	if local.Episodes != 0 {
		drama.TotalEpisode, drama.EpisodeCount = nil, nil
	}
	if local.Category != "" {
		drama.CategoryName = ""
	}
	if local.Heat != "" {
		drama.Heat = ""
	}
	if local.Views != "" {
		drama.Views = ""
	}
	if local.OnlineDate != "" {
		drama.OnlineDate = ""
	}
	if len(local.Tags) > 0 {
		drama.Tags = nil
	}
	if local.ReleaseStatus != "" {
		drama.ReleaseStatus = ""
	}
	if local.VIP != nil {
		drama.VIP = nil
	}
	return drama
}

func (app *UIApp) libraryExchangeCountsLocked(result *libraryImportResult) map[string]int {
	counts := map[string]int{}
	for _, drama := range app.dramas {
		counts[dramaProvider(drama)]++
	}
	for source, count := range counts {
		result.Sources[source] = count
	}
	return counts
}

func (app *UIApp) importLibraryExchange(ctx context.Context, document libraryExchange) (libraryImportResult, error) {
	result := libraryImportResult{Sources: map[string]int{}}
	incoming := make([]Drama, 0, len(document.Dramas))
	for _, entry := range document.Dramas {
		drama, valid := libraryExchangeDramaToDrama(entry)
		if !valid {
			result.Rejected++
			continue
		}
		if !dramaAllowed(ctx, drama.ID, drama.Source) {
			result.Denied++
			continue
		}
		incoming = append(incoming, drama)
	}
	if len(incoming) == 0 {
		app.mu.Lock()
		app.libraryExchangeCountsLocked(&result)
		result.Total = len(app.dramas)
		app.mu.Unlock()
		return result, nil
	}
	app.mu.Lock()
	app.normalizeDramaCovers(incoming)
	positions := make(map[string]int, len(app.dramas))
	for index, drama := range app.dramas {
		positions[drama.ID] = index
	}
	touched := false
	for _, drama := range incoming {
		if position, found := positions[drama.ID]; found {
			before, _ := libraryExchangeDramaFromDrama(app.dramas[position])
			merged := mergeDramaMetadata(app.dramas[position], libraryExchangeClearCovered(before, drama))
			if !reflect.DeepEqual(merged, app.dramas[position]) {
				app.dramas[position] = merged
				touched = true
			}
			if after, valid := libraryExchangeDramaFromDrama(merged); valid && !reflect.DeepEqual(before, after) {
				result.Merged++
			}
			continue
		}
		positions[drama.ID] = len(app.dramas)
		app.dramas = append(app.dramas, drama)
		result.Imported++
	}
	counts := app.libraryExchangeCountsLocked(&result)
	if result.Imported == 0 && !touched {
		result.Total = len(app.dramas)
		app.mu.Unlock()
		return result, nil
	}
	if app.librarySources == nil {
		app.librarySources = map[string]librarySourceState{}
	}
	for source, state := range app.librarySources {
		if count, found := counts[source]; found {
			state.Count = count
		} else {
			state.Count = 0
		}
		app.librarySources[source] = state
	}
	for source, count := range counts {
		state := app.librarySources[source]
		state.Count = count
		if state.Status == "" {
			state.Status = "ready"
		}
		app.librarySources[source] = state
		result.Sources[source] = count
	}
	app.loadedAt = time.Now()
	app.libraryError = librarySourceErrors(app.librarySources)
	app.libraryDirty = true
	app.libraryRevision++
	result.Total = len(app.dramas)
	app.mu.Unlock()
	if err := app.persistLibrary(); err != nil {
		return result, err
	}
	return result, nil
}
