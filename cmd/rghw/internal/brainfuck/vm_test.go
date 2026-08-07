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

func TestVerifyIntegrityEmptyPayload(t *testing.T) {
	err := VerifyIntegrity([]byte{})
	if err != nil {
		t.Fatalf("expected no error for empty payload, got: %v", err)
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

func TestDecrementCell(t *testing.T) {
	program := []byte("+++++[-]")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(out) != 0 {
		t.Fatalf("expected empty output, got %q", string(out))
	}
}

func TestLoopSkippedWhenZero(t *testing.T) {
	program := []byte("[-]")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(out) != 0 {
		t.Fatalf("expected empty output, got %q", string(out))
	}
}

func TestMoveLeftThenRight(t *testing.T) {
	program := []byte(">+>.+.")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(out) != "\x00\x01" {
		t.Fatalf("got %q, want %q", string(out), "\x00\x01")
	}
}

func TestVerifyIntegrityRunError(t *testing.T) {
	program := []byte(",")
	vm := NewVM(program)
	_, err := vm.Run()
	if err == nil {
		t.Fatalf("expected error for unsupported input instruction")
	}
}
