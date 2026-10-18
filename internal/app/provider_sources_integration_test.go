package app

import (
	"encoding/base64"
	"strings"
	"testing"

	"juku/internal/webui"
)

func TestProviderOnlineSourcesCoverRegisteredDuanjuCatalog(t *testing.T) {
	online := map[string]bool{}
	for _, source := range providerOnlineSources() {
		online[source] = true
	}
	for _, source := range []string{"cloudfront", sourceHuangguoAI, sourceHuangguoVideo, sourceHuangdou, sourceHongguo, sourceHuangju, sourceYeguo, sourceDSD} {
		if !online[source] || !onlineProviderSource(source) {
			t.Fatalf("catalog source %q is missing from the online list", source)
		}
	}
	choices := map[string]bool{}
	for _, choice := range accountSourceChoices {
		choices[choice.ID] = true
	}
	for _, spec := range duanjuProviderCatalog {
		if !online[spec.ID] || !onlineProviderSource(spec.ID) {
			t.Fatalf("duanju source %q is missing from the online list", spec.ID)
		}
		if !choices[spec.ID] {
			t.Fatalf("duanju source %q is missing from account choices", spec.ID)
		}
	}
	for _, choice := range accountSourceChoices {
		if choice.ID == "huangguo" {
			continue
		}
		if !online[choice.ID] {
			t.Fatalf("account source %q has no online catalog", choice.ID)
		}
	}
}

func TestProviderOnlineSourceCapabilitiesStayConsistent(t *testing.T) {
	search := map[string]bool{}
	for _, source := range providerSearchSources() {
		if !searchableProvider(source) || !onlineProviderSource(source) {
			t.Fatalf("search source %q is unusable", source)
		}
		search[source] = true
	}
	for _, spec := range duanjuProviderCatalog {
		if search[spec.ID] != duanjuSupportsSearch(spec.ID) {
			t.Fatalf("duanju source %q search support is inconsistent", spec.ID)
		}
	}
	if !search[sourceHongguo] || !search[sourceHuangju] || !search[sourceYeguo] || !search[sourceDSD] {
		t.Fatal("catalog providers are missing from online search")
	}
	paged := map[string]bool{}
	for _, source := range providerPagedSources() {
		if !paginatedProvider(source) || !onlineProviderSource(source) {
			t.Fatalf("paged source %q is unusable", source)
		}
		paged[source] = true
	}
	for _, source := range []string{sourceHuangju, sourceYeguo, sourceDSD} {
		if !paged[source] {
			t.Fatalf("catalog source %q cannot continue loading", source)
		}
	}
	for _, spec := range duanjuProviderCatalog {
		if paged[spec.ID] != spec.Paged {
			t.Fatalf("duanju source %q paging support is inconsistent", spec.ID)
		}
	}
	for _, source := range providerOnlineSources() {
		if source == "cloudfront" {
			continue
		}
		if !supportsDramaMetadata(Drama{Source: source}) {
			t.Fatalf("online source %q cannot refresh drama metadata", source)
		}
	}
}

func TestEmbeddedSourceListsCoverEveryOnlineProvider(t *testing.T) {
	read := func(name string) string {
		t.Helper()
		body, err := webui.Assets.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		return string(body)
	}
	searchScript := read("online-search.js")
	for _, source := range providerSearchSources() {
		if !strings.Contains(searchScript, "'"+source+"'") {
			t.Errorf("online-search.js is missing %q", source)
		}
	}
	coreScript := read("ui-core.js")
	for _, source := range providerOnlineSources() {
		if !strings.Contains(coreScript, source+":'") && !strings.Contains(coreScript, "'"+source+"':") {
			t.Errorf("ui-core.js cannot recognize source %q", source)
		}
	}
	libraryScript := read("library.js")
	for _, choice := range accountSourceChoices {
		if !strings.Contains(libraryScript, "'"+choice.ID+"'") {
			t.Errorf("library.js is missing %q", choice.ID)
		}
	}
}

func TestDuanjuSourceKeysStaySafeAndReversible(t *testing.T) {
	intro := "平安村的赵大山，凭着一手好厨艺，和媳妇在镇上开的小饭店生意红火/食客络绎不绝？日子过得有声有色"
	key := duanjuKeyWithPayload("494853072879618", intro)
	if strings.ContainsAny(key, "\x00\r\n\t /\\?#") || len(key) > 512 {
		t.Fatalf("source key is not safe: %q", key)
	}
	if duanjuKeyBaseID(key) != "494853072879618" || !strings.Contains(duanjuKeyPayloadValue(key), "赵大山") {
		t.Fatalf("source key payload did not round-trip: %q", key)
	}
	id := providerDramaID(sourceXingguo, key)
	if !validPriorityDramaID(id) {
		t.Fatalf("duanju priority id rejected: %q", id)
	}
	canonical, source, ok := playbackHistoryIdentity(id)
	if !ok || source != sourceXingguo || canonical != id {
		t.Fatalf("duanju id is unusable for watching history: %q %q %v", canonical, source, ok)
	}
	sample, sourceID, ok := splitProviderDramaID(id)
	if !ok || sample != sourceXingguo || sourceID != key {
		t.Fatalf("duanju id is unusable as a provider id: %q %q %v", sample, sourceID, ok)
	}
	long := strings.Repeat("很长的简介", 200)
	trimmed := duanjuKeyWithPayload("123", long)
	if len(trimmed) > duanjuKeyPayloadLimit {
		t.Fatalf("payload is too long: %d", len(trimmed))
	}
	if value := duanjuKeyPayloadValue(trimmed); len([]rune(value)) != duanjuKeyPayloadRunes {
		t.Fatalf("payload was not truncated to %d runes: %d", duanjuKeyPayloadRunes, len([]rune(value)))
	}
	fanguo := duanjuKeyWithPayload("100280", "qingting")
	if fanguo != "100280~"+base64.RawURLEncoding.EncodeToString([]byte("qingting")) {
		t.Fatalf("unexpected fanguo key: %q", fanguo)
	}
	if duanjuKeyBaseID("100280") != "100280" || duanjuKeyPayloadValue("100280") != "" {
		t.Fatal("a plain source id must stay plain")
	}
	if duanjuKeyWithPayload("9", "") != "9" || duanjuKeyWithPayload("", "qingting") != "" {
		t.Fatal("empty payloads must not change the source id")
	}
}
