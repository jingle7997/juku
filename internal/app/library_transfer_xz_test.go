package app

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestLibraryExchangeXZRoundTrip(t *testing.T) {
	document := libraryExchange{App: libraryExchangeApp, Kind: libraryExchangeKind, Version: libraryExchangeVersion, Count: 2, Dramas: []libraryExchangeDrama{{ID: "hongguo:1", Source: "hongguo", Title: "样本剧"}, {ID: "huangdou:2", Source: "huangdou", Title: "样本剧二"}}}
	payload, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := libraryExchangeCompress(payload)
	if err != nil {
		t.Fatalf("compress failed: %v", err)
	}
	if !libraryExchangeIsXZ(compressed) {
		t.Fatalf("output is not an xz stream: % x", compressed[:6])
	}
	if len(compressed) == 0 {
		t.Fatal("compressed output is empty")
	}
	restored, err := libraryExchangeDecompress(compressed)
	if err != nil {
		t.Fatalf("decompress failed: %v", err)
	}
	var decoded libraryExchange
	if err := json.Unmarshal(restored, &decoded); err != nil {
		t.Fatalf("restored payload is not valid json: %v", err)
	}
	if decoded.Count != document.Count || len(decoded.Dramas) != len(document.Dramas) || decoded.Dramas[0].Title != "样本剧" {
		t.Fatalf("round trip lost data: %+v", decoded)
	}
}

func TestLibraryExchangeRejectsCorruptXZ(t *testing.T) {
	if _, err := libraryExchangeDecompress([]byte{0xFD, '7', 'z', 'X', 'Z', 0x00, 1, 2, 3, 4}); err == nil {
		t.Fatal("corrupt xz payload should fail")
	}
	if libraryExchangeIsXZ([]byte(`{"kind":"library"}`)) {
		t.Fatal("plain json must not be detected as xz")
	}
	if libraryExchangeIsXZ(nil) {
		t.Fatal("empty payload must not be detected as xz")
	}
}

func TestLibraryExchangeDecompressIsBounded(t *testing.T) {
	oversized := bytes.Repeat([]byte("x"), libraryExchangeBytes+1024)
	compressed, err := libraryExchangeCompress(oversized)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := libraryExchangeDecompress(compressed); err == nil {
		t.Fatal("oversized decompressed payload should be rejected")
	}
}

func TestLibraryImportAcceptsXZAndLegacyJSON(t *testing.T) {
	document := libraryExchange{App: libraryExchangeApp, Kind: libraryExchangeKind, Version: libraryExchangeVersion, Count: 1, Dramas: []libraryExchangeDrama{{ID: "hongguo:1", Source: "hongguo", Title: "样本剧"}}}
	payload, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := libraryExchangeCompress(payload)
	if err != nil {
		t.Fatal(err)
	}
	app := &UIApp{}
	for _, probe := range []struct {
		name        string
		contentType string
		body        []byte
		status      int
	}{
		{"xz", "application/x-xz", compressed, http.StatusOK},
		{"xz-sniffed", "application/octet-stream", compressed, http.StatusOK},
		{"legacy-json", "application/json", payload, http.StatusOK},
		{"unsupported", "text/plain", compressed, http.StatusUnsupportedMediaType},
		{"corrupt-xz", "application/x-xz", []byte{0xFD, '7', 'z', 'X', 'Z', 0x00, 9, 9}, http.StatusBadRequest},
	} {
		request := httptest.NewRequest(http.MethodPost, "/api/ui/admin/library", bytes.NewReader(probe.body))
		request.Header.Set("Content-Type", probe.contentType)
		recorder := httptest.NewRecorder()
		app.handleLibraryImport(recorder, request)
		if recorder.Code != probe.status {
			t.Fatalf("%s: expected %d, got %d (%s)", probe.name, probe.status, recorder.Code, recorder.Body.String())
		}
	}
}

func TestLibraryImportRejectsUnsupportedPayload(t *testing.T) {
	app := &UIApp{}
	request := httptest.NewRequest(http.MethodPost, "/api/ui/admin/library", bytes.NewReader([]byte("<html>nope</html>")))
	request.Header.Set("Content-Type", "application/octet-stream")
	recorder := httptest.NewRecorder()
	app.handleLibraryImport(recorder, request)
	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d (%s)", recorder.Code, recorder.Body.String())
	}
}

func TestLibraryExchangeCompressPrefersHighestPreset(t *testing.T) {
	document := libraryExchange{App: libraryExchangeApp, Kind: libraryExchangeKind, Version: libraryExchangeVersion, Count: 400}
	for index := 0; index < 400; index++ {
		document.Dramas = append(document.Dramas, libraryExchangeDrama{
			ID:          fmt.Sprintf("hongguo:%d", index),
			Source:      "hongguo",
			Title:       fmt.Sprintf("都市逆袭第%d部", index),
			Description: "这是一部都市逆袭题材的短剧，讲述主角在遭遇背叛之后逆风翻盘的故事。",
			Category:    "都市",
		})
	}
	payload, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	preferred, err := libraryExchangeCompress(payload)
	if err != nil {
		t.Fatalf("compress failed: %v", err)
	}
	pure, err := libraryExchangeCompressPure(payload)
	if err != nil {
		t.Fatal(err)
	}
	if !libraryExchangeIsXZ(preferred) || !libraryExchangeIsXZ(pure) {
		t.Fatal("both encoders must emit an xz stream")
	}
	if restored, err := libraryExchangeDecompress(preferred); err != nil || !bytes.Equal(restored, payload) {
		t.Fatalf("preferred encoder round trip failed: %v", err)
	}
	if libraryExchangeXZBinary() != "" && len(preferred) >= len(pure) {
		t.Fatalf("preferred encoder must not be larger than the fallback: %d >= %d", len(preferred), len(pure))
	}

	binaries, path := libraryExchangeXZBinaries, os.Getenv("PATH")
	libraryExchangeXZBinaries = nil
	t.Setenv("PATH", filepath.Join(t.TempDir(), "empty"))
	t.Cleanup(func() { libraryExchangeXZBinaries = binaries })
	if libraryExchangeXZBinary() != "" {
		t.Fatal("expected no external xz to be discoverable")
	}
	fallback, err := libraryExchangeCompress(payload)
	if err != nil {
		t.Fatalf("fallback compress failed: %v", err)
	}
	if restored, err := libraryExchangeDecompress(fallback); err != nil || !bytes.Equal(restored, payload) {
		t.Fatalf("fallback round trip failed: %v", err)
	}
	t.Setenv("PATH", path)
}

func TestLibraryExchangeXZInteroperatesWithSystemXZ(t *testing.T) {
	if _, err := exec.LookPath("xz"); err != nil {
		t.Skip("system xz is not installed")
	}
	document := libraryExchange{App: libraryExchangeApp, Kind: libraryExchangeKind, Version: libraryExchangeVersion, Count: 1, Dramas: []libraryExchangeDrama{{ID: "hongguo:1", Source: "hongguo", Title: "系统 xz 互通样本"}}}
	payload, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	mine, err := libraryExchangeCompress(payload)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	fromGo := filepath.Join(dir, "from-go.xz")
	if err := os.WriteFile(fromGo, mine, 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("xz", "-dc", fromGo).Output()
	if err != nil {
		t.Fatalf("system xz could not read our stream: %v", err)
	}
	if string(out) != string(payload) {
		t.Fatalf("system xz produced different bytes:\n%s", out)
	}
	source := filepath.Join(dir, "payload.json")
	if err := os.WriteFile(source, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	fromSystem := filepath.Join(dir, "from-system.xz")
	compressed, err := os.Create(fromSystem)
	if err != nil {
		t.Fatal(err)
	}
	command := exec.Command("xz", "-c", source)
	command.Stdout = compressed
	runErr := command.Run()
	closeErr := compressed.Close()
	if runErr != nil {
		t.Fatalf("system xz compress failed: %v", runErr)
	}
	if closeErr != nil {
		t.Fatal(closeErr)
	}
	system, err := os.ReadFile(fromSystem)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := libraryExchangeDecompress(system)
	if err != nil {
		t.Fatalf("we could not read the system xz stream: %v", err)
	}
	if string(restored) != string(payload) {
		t.Fatal("restored bytes differ from the original payload")
	}
}
