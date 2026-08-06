package version

import "testing"

func TestVersionNonEmpty(t *testing.T) {
	if Version == "" {
		t.Fatal("Version must not be empty")
	}
}

func TestVersionMilestone6(t *testing.T) {
	if Version != "0.2.0-milestone6" {
		t.Fatalf("Version = %q, want %q", Version, "0.2.0-milestone6")
	}
}
