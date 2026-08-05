// Package geom normalizes raw geometry into a standard em-square canvas.
package geom

import "math"

// Normalization constants (Stage 3 of the architecture): a 1024-unit
// em-square with the baseline at 800, 32-unit side bearings, and a 16-unit
// top margin. Every coordinate stays positive and the glyph bottom sits on
// the baseline.
const (
	EmSize       = 1024.0
	Baseline     = 800.0
	LeftBearing  = 32.0
	RightBearing = 32.0
	TopMargin    = 16.0
)

// Segment is an explicit line segment in glyph space.
type Segment struct {
	X1 float64 `json:"x1"`
	Y1 float64 `json:"y1"`
	X2 float64 `json:"x2"`
	Y2 float64 `json:"y2"`
}

// GeometryPayload is the geometry object of a GeometryExpanded event.
type GeometryPayload struct {
	Kind           string    `json:"kind"`
	Segments       []Segment `json:"segments"`
	AdvanceWidth   float64   `json:"advanceWidth"`
	GeometrySha256 string    `json:"geometrySha256"`
}

// Normalized holds the result of normalizing one glyph.
type Normalized struct {
	Segments []Segment
	ViewBox  struct {
		Width  float64 `json:"width"`
		Height float64 `json:"height"`
	}
	Baseline float64
}

// Quantize rounds to three decimal places so outputs are stable across
// runs and platforms.
func Quantize(value float64) float64 {
	return math.Round(value*1000) / 1000
}

// Normalize translates a glyph's segments into positive canvas space,
// scales them into the em-square content box preserving aspect ratio,
// aligns the bottom to the baseline, and quantizes the result. Gap geometry
// produces an empty (non-nil) result; the layout metadata lives in the
// artifact.
func Normalize(payload GeometryPayload) Normalized {
	result := Normalized{Segments: []Segment{}}
	result.ViewBox.Width = EmSize
	result.ViewBox.Height = EmSize
	result.Baseline = Baseline
	if payload.Kind == "GAP_GEOMETRY" || len(payload.Segments) == 0 {
		return result
	}

	xMin, yMin, xMax, yMax := bounds(payload.Segments)
	glyphWidth := xMax - xMin
	glyphHeight := yMax - yMin
	if glyphWidth <= 0 {
		glyphWidth = 1
	}
	if glyphHeight <= 0 {
		glyphHeight = 1
	}
	contentWidth := EmSize - LeftBearing - RightBearing
	contentHeight := Baseline - TopMargin
	scale := math.Min(contentWidth/glyphWidth, contentHeight/glyphHeight)

	for _, segment := range payload.Segments {
		result.Segments = append(result.Segments, Segment{
			X1: Quantize(LeftBearing + (segment.X1-xMin)*scale),
			Y1: Quantize(Baseline - (segment.Y1-yMin)*scale),
			X2: Quantize(LeftBearing + (segment.X2-xMin)*scale),
			Y2: Quantize(Baseline - (segment.Y2-yMin)*scale),
		})
	}
	return result
}

func bounds(segments []Segment) (xMin, yMin, xMax, yMax float64) {
	xMin, yMin = math.Inf(1), math.Inf(1)
	xMax, yMax = math.Inf(-1), math.Inf(-1)
	for _, segment := range segments {
		xMin = math.Min(xMin, math.Min(segment.X1, segment.X2))
		yMin = math.Min(yMin, math.Min(segment.Y1, segment.Y2))
		xMax = math.Max(xMax, math.Max(segment.X1, segment.X2))
		yMax = math.Max(yMax, math.Max(segment.Y1, segment.Y2))
	}
	return xMin, yMin, xMax, yMax
}
