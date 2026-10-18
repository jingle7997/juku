package app

import "testing"

func TestMergeSourceDramasRemovesConfirmedLegacyHuangguoDuplicate(t *testing.T) {
	legacy := Drama{ID: "legacy-cloudfront-1", Title: "AI极品家丁", ChannelName: "旧黄果"}
	current := Drama{ID: "huangguoai:365", Source: sourceHuangguoAI, SourceID: "365", Title: "AI极品家丁", ChannelName: "huangguoai.ai"}
	other := Drama{ID: "legacy-cloudfront-2", Title: "另一部旧剧"}

	merged := mergeSourceDramas([]Drama{legacy, other}, []Drama{current}, nil, "")
	if len(merged) != 2 {
		t.Fatalf("merged %d dramas, want 2: %+v", len(merged), merged)
	}
	for _, drama := range merged {
		if drama.ID == legacy.ID {
			t.Fatal("legacy cloudfront duplicate was retained")
		}
	}
}

func TestMergeSourceDramasKeepsUnmatchedLegacyCloudfront(t *testing.T) {
	legacy := Drama{ID: "legacy-cloudfront-1", Title: "旧剧"}
	current := Drama{ID: "huangguoai:365", Source: sourceHuangguoAI, SourceID: "365", Title: "新剧"}

	merged := mergeSourceDramas([]Drama{legacy}, []Drama{current}, nil, "")
	if len(merged) != 2 {
		t.Fatalf("unmatched legacy drama was removed: %+v", merged)
	}
}
