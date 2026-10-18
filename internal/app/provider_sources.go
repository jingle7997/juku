package app

import (
	"context"
	"errors"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

const (
	sourceHuangju = "huangju"
	sourceYeguo   = "yeguo"
	sourceDSD     = "dsd"
)

const providerCatalogFanoutWorkers = 4

var webProviderNumericID = regexp.MustCompile(`^[1-9][0-9]{0,17}$`)

type providerCategory struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

var providerOnlineSourceIDs = func() []string {
	sources := []string{"cloudfront", sourceHuangguoAI, sourceHuangguoVideo, sourceHuangdou, sourceHongguo, sourceHuangju, sourceYeguo, sourceDSD}
	for _, spec := range duanjuProviderCatalog {
		sources = append(sources, spec.ID)
	}
	return sources
}()

func providerOnlineSources() []string {
	return append([]string{}, providerOnlineSourceIDs...)
}

func onlineProviderSource(source string) bool {
	source = canonicalProviderSource(source)
	for _, candidate := range providerOnlineSourceIDs {
		if candidate == source {
			return true
		}
	}
	return false
}

func searchableProvider(source string) bool {
	source = canonicalProviderSource(source)
	if source == sourceHongguo || paginatedProvider(source) {
		return true
	}
	return isDuanjuProviderSource(source) && duanjuSupportsSearch(source)
}

func providerSearchSources() []string {
	sources := make([]string, 0, len(providerOnlineSourceIDs))
	for _, candidate := range providerOnlineSourceIDs {
		if searchableProvider(candidate) {
			sources = append(sources, candidate)
		}
	}
	return sources
}

func providerPagedSources() []string {
	sources := make([]string, 0, len(providerOnlineSourceIDs))
	for _, candidate := range providerOnlineSourceIDs {
		if paginatedProvider(candidate) {
			sources = append(sources, candidate)
		}
	}
	return sources
}

func providerDetailMetadataSource(source string) bool {
	source = canonicalProviderSource(source)
	return source == sourceHuangju || source == sourceYeguo || source == sourceDSD || isDuanjuProviderSource(source)
}

func (d *Downloader) fetchOnlineProviderDramas(ctx context.Context, source, category string) ([]Drama, error) {
	source = canonicalProviderSource(source)
	categories := []string{category}
	if strings.TrimSpace(category) == "" {
		categories = d.providerCatalogCategories(ctx, source)
	}
	if len(categories) <= 1 {
		return d.fetchOnlineProviderCategory(ctx, source, categories[0])
	}
	type outcome struct {
		items []Drama
		err   error
	}
	outcomes := make([]outcome, len(categories))
	slots := make(chan struct{}, providerCatalogFanoutWorkers)
	var group sync.WaitGroup
	for index, current := range categories {
		group.Add(1)
		go func(index int, current string) {
			defer group.Done()
			select {
			case slots <- struct{}{}:
				defer func() { <-slots }()
			case <-ctx.Done():
				outcomes[index].err = ctx.Err()
				return
			}
			categoryCtx := context.WithValue(ctx, libraryCategoryKey{}, current)
			outcomes[index].items, outcomes[index].err = d.fetchOnlineProviderCategory(categoryCtx, source, current)
		}(index, current)
	}
	group.Wait()
	items := []Drama{}
	var failures []error
	for _, entry := range outcomes {
		items = mergeSourceDramas(items, entry.items, nil, source)
		if entry.err != nil {
			failures = append(failures, entry.err)
		}
	}
	if items == nil {
		items = []Drama{}
	}
	return items, errors.Join(failures...)
}

func (d *Downloader) fetchOnlineProviderCategory(ctx context.Context, source, category string) ([]Drama, error) {
	if source == sourceXingguo && category == xingguoWalkCategory {
		return d.fetchXingguoWalkUpdate(ctx)
	}
	if paginatedProvider(source) {
		return d.fetchPagedProviderDramas(ctx, source, category)
	}
	items, _, err := d.fetchProviderCatalogPage(ctx, source, 1, category, "")
	if err != nil {
		return nil, err
	}
	if items == nil {
		items = []Drama{}
	}
	return items, nil
}

func (d *Downloader) providerCatalogCategories(ctx context.Context, source string) []string {
	source = canonicalProviderSource(source)
	if !isDuanjuProviderSource(source) || duanjuBrowsesAllInOneFeed(source) {
		return []string{""}
	}
	if source == sourceXingguo {
		return []string{xingguoWalkCategory}
	}
	categories := d.duanjuCatalogCategories(ctx, source)
	if len(categories) == 0 {
		return []string{""}
	}
	return categories
}

func providerValueText(value any) string {
	return mapString(map[string]any{"value": value}, "value")
}

func webProviderInteger(value any, maximum int) (int, bool) {
	number, err := strconv.Atoi(providerValueText(value))
	return number, err == nil && number >= 0 && number <= maximum
}

func validProviderCategory(source, category string) bool {
	if category == "" {
		return true
	}
	if len(category) > 128 || strings.TrimSpace(category) != category || strings.ContainsAny(category, "|/\\\x00\r\n") {
		return false
	}
	switch source {
	case sourceHongguo:
		for _, genre := range hongguoAppGenres {
			if category == genre.key {
				return true
			}
		}
		return false
	case sourceHuangju:
		return category == huangjuNewestCategory || validHuangjuID(category) && !strings.HasPrefix(category, "@")
	case sourceYeguo:
		return validYeguoCategory(category)
	case sourceDSD:
		return webProviderNumericID.MatchString(category)
	}
	if isDuanjuProviderSource(source) {
		return validDuanjuCategory(source, category)
	}
	return false
}

func hongguoProviderCategories() []providerCategory {
	categories := []providerCategory{{Name: "全部"}}
	for _, genre := range hongguoAppGenres {
		categories = append(categories, providerCategory{ID: genre.key, Name: genre.name})
	}
	return categories
}

func (d *Downloader) fetchProviderCategories(ctx context.Context, source string) ([]providerCategory, error) {
	if !sourceAllowed(ctx, source) {
		return nil, errors.New("当前账号无权访问该站源")
	}
	switch canonicalProviderSource(source) {
	case sourceHongguo:
		return hongguoProviderCategories(), nil
	case sourceHuangju:
		return d.fetchHuangjuCategories(ctx)
	case sourceYeguo:
		return d.fetchYeguoCategories(ctx)
	case sourceDSD:
		return d.fetchDSDCategories(ctx, false)
	}
	return nil, errors.New("该站源暂未提供实时分类")
}

func paginatedProvider(source string) bool {
	return source == sourceHuangju || source == sourceYeguo || source == sourceDSD || duanjuSupportsPaging(source)
}

func (d *Downloader) fetchProviderCatalogPage(ctx context.Context, source string, page int, category, query string) ([]Drama, bool, error) {
	if !sourceAllowed(ctx, source) {
		return nil, false, errors.New("当前账号无权访问该站源")
	}
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuCatalogPage(ctx, page, category, query)
	case sourceYeguo:
		return d.fetchYeguoCatalogPage(ctx, page, category, query)
	case sourceDSD:
		return d.fetchDSDCatalogPage(ctx, page, category, query)
	}
	if isDuanjuProviderSource(source) {
		if query != "" {
			items, err := d.searchDuanju(ctx, source, query)
			return items, false, err
		}
		return d.fetchDuanjuCatalogPage(ctx, source, page, category)
	}
	return nil, false, errors.New("该站源不支持在线分页查询")
}

func (d *Downloader) fetchProviderDetail(ctx context.Context, source, id string) (Drama, []Chapter, error) {
	if !sourceAllowed(ctx, source) {
		return Drama{}, nil, errors.New("当前账号无权访问该站源")
	}
	switch source {
	case sourceHuangju:
		return d.fetchHuangjuDetail(ctx, id)
	case sourceYeguo:
		return d.fetchYeguoDetail(ctx, id)
	case sourceDSD:
		return d.fetchDSDDetail(ctx, id)
	}
	if isDuanjuProviderSource(source) {
		return d.fetchDuanjuDetail(ctx, source, id)
	}
	return Drama{}, nil, errors.New("该站源不支持详情查询")
}
