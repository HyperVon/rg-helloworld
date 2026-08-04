package version

import "testing"

func TestVersionNonEmpty(t *testing.T) {
	if Version == "" {
		t.Fatal("Version must not be empty")
	}
}

func TestVersionSkeleton(t *testing.T) {
	if Version != "0.0.0-skeleton" {
		t.Fatalf("Version = %q, want %q", Version, "0.0.0-skeleton")
	}
}
