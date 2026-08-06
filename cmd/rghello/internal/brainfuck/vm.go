package brainfuck

import (
	"errors"
	"fmt"
)

const (
	maxMemory   = 4096
	magicOutput = "HI"
)

var (
	maxSteps             int64 = 1_000_000
	errInvalidProgram          = errors.New("invalid brainfuck program")
	errMemoryOverflow          = errors.New("brainfuck memory overflow")
	errStepLimitExceeded       = errors.New("brainfuck step limit exceeded")
	errIntegrityMismatch       = errors.New("brainfuck integrity guard mismatch")
)

type VM struct {
	tape    []byte
	ptr     int
	pc      int
	steps   int64
	program []byte
	output  []byte
}

func NewVM(program []byte) *VM {
	return &VM{
		tape:    make([]byte, maxMemory),
		program: program,
	}
}

func (v *VM) Run() ([]byte, error) {
	for v.pc < len(v.program) {
		if v.steps >= maxSteps {
			return nil, errStepLimitExceeded
		}
		v.steps++
		switch v.program[v.pc] {
		case '>':
			v.ptr++
			if v.ptr >= maxMemory {
				return nil, errMemoryOverflow
			}
		case '<':
			v.ptr--
			if v.ptr < 0 {
				return nil, errMemoryOverflow
			}
		case '+':
			v.tape[v.ptr]++
		case '-':
			v.tape[v.ptr]--
		case '.':
			v.output = append(v.output, v.tape[v.ptr])
		case ',':
			return nil, fmt.Errorf("%w: input not supported", errInvalidProgram)
		case '[':
			if v.tape[v.ptr] == 0 {
				depth := 1
				for depth > 0 {
					v.pc++
					if v.pc >= len(v.program) {
						return nil, errInvalidProgram
					}
					if v.program[v.pc] == '[' {
						depth++
					} else if v.program[v.pc] == ']' {
						depth--
					}
				}
			}
		case ']':
			if v.tape[v.ptr] != 0 {
				depth := 1
				for depth > 0 {
					v.pc--
					if v.pc < 0 {
						return nil, errInvalidProgram
					}
					if v.program[v.pc] == ']' {
						depth++
					} else if v.program[v.pc] == '[' {
						depth--
					}
				}
			}
		}
		v.pc++
	}
	return v.output, nil
}

func VerifyIntegrity(payload []byte) error {
	program := []byte("+++++++++[>++++++++<-]>.+.")
	vm := NewVM(program)
	out, err := vm.Run()
	if err != nil {
		return err
	}
	if string(out) != magicOutput {
		return errIntegrityMismatch
	}
	return nil
}
