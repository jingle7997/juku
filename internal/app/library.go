package app

import (
	"fmt"
	"sort"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

type libraryLoadError struct {
	failures map[string]error
}

func (failure *libraryLoadError) Error() string {
	var messages []string
	for source, cause := range failure.failures {
		messages = append(messages, fmt.Sprintf("%s 获取失败: %v", source, publicError(cause)))
	}
	sort.Strings(messages)
	return strings.Join(messages, "\n")
}

func dramaProvider(drama Drama) string {
	if source := canonicalProviderSource(drama.Source); source != "" {
		return source
	}
	if source, _, ok := splitProviderDramaID(drama.ID); ok {
		return source
	}
	return "cloudfront"
}

func mergeLoadedDramas(cached, fresh []Drama, loadErr error) []Drama {
	return mergeSourceDramas(cached, fresh, loadErr, "")
}

func matchesSourceFilter(provider, source string) bool {
	if source == "" {
		return true
	}
	if source == "huangguo" {
		return provider == "cloudfront" || provider == sourceHuangguoAI || provider == sourceHuangguoVideo
	}
	return provider == source || provider == canonicalProviderSource(source)
}

func mergeSourceDramas(cached, fresh []Drama, loadErr error, source string) []Drama {
	merged := make([]Drama, 0, len(cached)+len(fresh))
	positions := make(map[string]int, cap(merged))
	for _, batch := range [][]Drama{cached, fresh} {
		for _, drama := range batch {
			if drama.ID == "" {
				continue
			}
			if position, found := positions[drama.ID]; found {
				merged[position] = mergeDramaMetadata(drama, merged[position])
			} else {
				positions[drama.ID] = len(merged)
				merged = append(merged, drama)
			}
		}
	}
	if replaced := replacedLegacyHuangguoTitles(fresh); len(replaced) > 0 {
		filtered := merged[:0]
		for _, drama := range merged {
			if dramaProvider(drama) == "cloudfront" && replaced[normalizedDramaTitle(drama.DisplayTitle())] {
				continue
			}
			filtered = append(filtered, drama)
		}
		merged = filtered
	}
	sort.SliceStable(merged, func(left, right int) bool { return merged[left].DisplayTitle() < merged[right].DisplayTitle() })
	return merged
}

func normalizedDramaTitle(title string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) || unicode.IsPunct(r) {
			return -1
		}
		return unicode.ToLower(r)
	}, norm.NFKC.String(strings.TrimSpace(title)))
}

func replacedLegacyHuangguoTitles(fresh []Drama) map[string]bool {
	replaced := map[string]bool{}
	for _, drama := range fresh {
		if dramaProvider(drama) != sourceHuangguoAI {
			continue
		}
		if title := normalizedDramaTitle(drama.DisplayTitle()); title != "" {
			replaced[title] = true
		}
	}
	return replaced
}
