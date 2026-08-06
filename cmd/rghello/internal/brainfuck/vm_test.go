package brainfuck

import (
	"strings"
	"testing"
)

func TestHelloWorld(t *testing.T) {
	program := []byte("++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(out) != "Hello World!" {
		t.Fatalf("got %q, want %q", string(out), "Hello World!")
	}
}

func TestStepLimit(t *testing.T) {
	oldMaxSteps := maxSteps
	defer func() { maxSteps = oldMaxSteps }()
	maxSteps = 10

	program := []byte("+[+]")
	vm := NewVM(program)
	_, err := vm.Run()
	if err != errStepLimitExceeded {
		t.Fatalf("expected step limit error, got: %v", err)
	}
}

func TestMemoryOverflowRight(t *testing.T) {
	program := []byte(strings.Repeat(">", maxMemory+1))
	vm := NewVM(program)
	_, err := vm.Run()
	if err != errMemoryOverflow {
		t.Fatalf("expected memory overflow, got: %v", err)
	}
}

func TestMemoryOverflowLeft(t *testing.T) {
	program := []byte(strings.Repeat("<", maxMemory+1))
	vm := NewVM(program)
	_, err := vm.Run()
	if err != errMemoryOverflow {
		t.Fatalf("expected memory overflow, got: %v", err)
	}
}

func TestVerifyIntegrityMatch(t *testing.T) {
	err := VerifyIntegrity([]byte("test-payload"))
	if err != nil {
		t.Fatalf("expected no error for matching integrity, got: %v", err)
	}
}

func TestVerifyIntegrityTamperedProgram(t *testing.T) {
	program := []byte("+++++++++[>++++++++<-]>+.-")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(out) == magicOutput {
		t.Fatalf("tampered program unexpectedly produced magic output %q", string(out))
	}
}

func TestEmptyProgram(t *testing.T) {
	vm := NewVM([]byte{})
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(out) != 0 {
		t.Fatalf("expected empty output, got %q", string(out))
	}
}
