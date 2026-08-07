package svg

import (
	"strings"
	"testing"

	"rghw.dev/vector-normalizer/internal/geom"
)

func TestBuildEmitsPolylineOnly(t *testing.T) {
	segments := []geom.Segment{
		{X1: 32, Y1: 800, X2: 32, Y2: 32},
	}
	content := Build(segments)
	if !strings.Contains(content, "<polyline") {
		t.Fatalf("expected polyline in %q", content)
	}
	if strings.Contains(content, "<text") || strings.Contains(content, "<font") {
		t.Fatalf("SVG must not contain text or font elements: %q", content)
	}
	if strings.Contains(content, "<path") {
		t.Fatalf("SVG must not contain path elements: %q", content)
	}
	if !strings.HasPrefix(content, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">`) {
		t.Fatalf("unexpected svg prefix: %q", content)
	}
	if !strings.HasSuffix(content, "</svg>") {
		t.Fatalf("unexpected svg suffix: %q", content)
	}
}

func TestBuildEmptySegments(t *testing.T) {
	content := Build(nil)
	if strings.Contains(content, "<polyline") {
		t.Fatalf("empty segments must not emit a polyline: %q", content)
	}
	if strings.Contains(content, "<text") {
		t.Fatalf("empty svg must not contain text: %q", content)
	}
}

func TestBuildDeterministic(t *testing.T) {
	segments := []geom.Segment{
		{X1: 32, Y1: 800, X2: 352, Y2: 32},
		{X1: 352, Y1: 800, X2: 672, Y2: 32},
	}
	first := Build(segments)
	second := Build(segments)
	if first != second {
		t.Fatalf("SVG is not deterministic:\n%s\n%s", first, second)
	}
	if !strings.Contains(first, "32.000,800.000 352.000,32.000") {
		t.Fatalf("fixed three-decimal formatting missing: %q", first)
	}
}

func TestSha256HexKnownValue(t *testing.T) {
	// sha256 of the empty string.
	if got := Sha256Hex(""); got != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" {
		t.Fatalf("Sha256Hex(empty) = %s", got)
	}
	if Sha256Hex("abc") != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
		t.Fatalf("Sha256Hex(abc) wrong")
	}
}
