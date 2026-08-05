package geom

import (
	"math"
	"testing"
)

func TestQuantizeRoundsToThreeDecimals(t *testing.T) {
	cases := map[float64]float64{
		1.23456:  1.235,
		0.0004:   0.0,
		1024.0:   1024.0,
		-0.0015:  -0.002,
		123.4567: 123.457,
	}
	for input, want := range cases {
		if got := Quantize(input); got != want {
			t.Fatalf("Quantize(%v) = %v, want %v", input, got, want)
		}
	}
}

func TestNormalizeDrawableGlyph(t *testing.T) {
	payload := GeometryPayload{
		Kind: "DRAWABLE_GEOMETRY",
		Segments: []Segment{
			{X1: 0.1, Y1: 0.0, X2: 0.1, Y2: 1.0},
			{X1: 0.9, Y1: 0.0, X2: 0.9, Y2: 1.0},
			{X1: 0.1, Y1: 0.5, X2: 0.9, Y2: 0.5},
		},
		AdvanceWidth: 1.0,
	}
	result := Normalize(payload)
	if len(result.Segments) != 3 {
		t.Fatalf("segments = %d, want 3", len(result.Segments))
	}
	if result.ViewBox.Width != EmSize || result.ViewBox.Height != EmSize {
		t.Fatalf("viewBox = %v, want %v", result.ViewBox, EmSize)
	}
	if result.Baseline != Baseline {
		t.Fatalf("baseline = %v, want %v", result.Baseline, Baseline)
	}
	for _, segment := range result.Segments {
		for _, value := range []float64{segment.X1, segment.Y1, segment.X2, segment.Y2} {
			if value < 0 {
				t.Fatalf("negative coordinate %v in positive canvas space", value)
			}
		}
	}
	// Glyph height 1.0 maps into the content box; the bottom (min y) sits
	// ON the baseline and the top (max y) stays at least the top margin
	// below the canvas edge. Canvas y grows downward.
	if got := result.Segments[0].Y1; got != Baseline {
		t.Fatalf("glyph bottom y = %v, want baseline %v", got, Baseline)
	}
	if got := result.Segments[0].Y2; got != TopMargin {
		t.Fatalf("glyph top y = %v, want top margin %v", got, TopMargin)
	}
	// Aspect ratio is preserved: width 0.8 (0.9-0.1) and height 1.0 keep
	// their ratio after scaling. Canvas y is inverted, so compare against
	// the absolute height.
	scale := (result.Segments[1].X1 - result.Segments[0].X1) / 0.8
	height := math.Abs(result.Segments[0].Y2 - result.Segments[0].Y1)
	if math.Abs(scale-height) > 0.001 {
		t.Fatalf("aspect ratio not preserved: scale=%v height=%v", scale, height)
	}
}

func TestNormalizeGapProducesNoSegments(t *testing.T) {
	result := Normalize(GeometryPayload{Kind: "GAP_GEOMETRY", AdvanceWidth: 0.6})
	if len(result.Segments) != 0 {
		t.Fatalf("gap segments = %d, want 0", len(result.Segments))
	}
	if result.Baseline != Baseline || result.ViewBox.Width != EmSize {
		t.Fatalf("gap layout defaults wrong: %+v", result)
	}
}

func TestNormalizeEmptySegments(t *testing.T) {
	result := Normalize(GeometryPayload{Kind: "DRAWABLE_GEOMETRY"})
	if len(result.Segments) != 0 {
		t.Fatalf("empty input produced %d segments", len(result.Segments))
	}
}

func TestNormalizeDeterministic(t *testing.T) {
	payload := GeometryPayload{
		Kind: "DRAWABLE_GEOMETRY",
		Segments: []Segment{
			{X1: 0.2, Y1: 0.1, X2: 0.8, Y2: 0.9},
		},
	}
	first := Normalize(payload)
	second := Normalize(payload)
	if len(first.Segments) != len(second.Segments) {
		t.Fatal("length differs")
	}
	for i := range first.Segments {
		if first.Segments[i] != second.Segments[i] {
			t.Fatalf("segment %d differs: %+v vs %+v", i, first.Segments[i], second.Segments[i])
		}
	}
}

func TestNormalizeDegenerateBounds(t *testing.T) {
	// A single vertical line has zero width; normalization must not divide
	// by zero and must keep coordinates finite.
	payload := GeometryPayload{
		Kind: "DRAWABLE_GEOMETRY",
		Segments: []Segment{
			{X1: 0.5, Y1: 0.0, X2: 0.5, Y2: 1.0},
		},
	}
	result := Normalize(payload)
	if len(result.Segments) != 1 {
		t.Fatalf("segments = %d, want 1", len(result.Segments))
	}
	for _, value := range []float64{result.Segments[0].X1, result.Segments[0].Y1,
		result.Segments[0].X2, result.Segments[0].Y2} {
		if math.IsNaN(value) || math.IsInf(value, 0) {
			t.Fatalf("non-finite coordinate %v", value)
		}
	}
}
