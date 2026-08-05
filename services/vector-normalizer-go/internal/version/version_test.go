package version

import "testing"

func TestVersionNonEmpty(t *testing.T) {
	if Version == "" {
		t.Fatal("Version must not be empty")
	}
}

func TestVersionMilestone5(t *testing.T) {
	if Version != "0.1.0-milestone5" {
		t.Fatalf("Version = %q, want %q", Version, "0.1.0-milestone5")
	}
}
