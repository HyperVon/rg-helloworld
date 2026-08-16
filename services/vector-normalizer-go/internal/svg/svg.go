// Package svg generates deterministic SVG for normalized glyph geometry.
package svg

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"

	"rghw.dev/vector-normalizer/internal/geom"
)

// Build renders each segment as its own polyline so disjoint contours are not
// joined by spurious connecting strokes. Only polyline elements are ever
// emitted: no text elements, no embedded fonts. Coordinates use fixed
// three-decimal formatting ordered by segment index, so the output is
// byte-stable.
func Build(segments []geom.Segment) string {
	var out strings.Builder
	out.WriteString(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">`)
	for _, segment := range segments {
		out.WriteString(`<polyline points="`)
		out.WriteString(format(segment.X1))
		out.WriteByte(',')
		out.WriteString(format(segment.Y1))
		out.WriteByte(' ')
		out.WriteString(format(segment.X2))
		out.WriteByte(',')
		out.WriteString(format(segment.Y2))
		out.WriteString(`" fill="none" stroke="#000000" stroke-width="8"/>`)
	}
	out.WriteString("</svg>")
	return out.String()
}

func format(value float64) string {
	return fmt.Sprintf("%.3f", value)
}

// Sha256Hex returns the lowercase hex SHA-256 of the content.
func Sha256Hex(content string) string {
	sum := sha256.Sum256([]byte(content))
	return hex.EncodeToString(sum[:])
}
