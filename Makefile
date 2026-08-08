# Rube Goldberg Hello World — top-level build orchestration.
#
# Milestone 0: repository skeleton. Targets for later milestones are defined
# but report "not implemented" until their milestone lands.
#
# Usage: make <target> [STRICT=1]
#   STRICT=1 makes missing toolchains a hard failure instead of a skip.

SHELL := /bin/bash
RUBY_PATH := $(if $(wildcard /opt/homebrew/opt/ruby/bin),/opt/homebrew/opt/ruby/bin/:)
export PATH := $(RUBY_PATH)$(PATH)

GO_CLI_DIR  := cmd/rghw
GO_NORM_DIR := services/vector-normalizer-go
KOTLIN_DIR  := services/run-orchestrator-kotlin
JAVA_DIR    := services/glyph-catalog-java
CPP_DIR     := services/geometry-engine-cpp
DOTNET_DIR  := services/rasterizer-dotnet
PYTHON_DIR  := services/image-pipeline-python
NODE_DIRS   := services/ocr-worker-node services/event-gateway-node services/telemetry-element
RUBY_DIRS    := services/adjudicator-ruby services/artifact-inspector-ruby
RUST_DIR    := services/phrase-assembler-rust

VENV      := .venv
BUILD_DIR := .local/build
CPP_BUILD := $(BUILD_DIR)/geometry-engine-cpp

CARGO   := $(if $(wildcard $(HOME)/.cargo/bin/cargo),$(HOME)/.cargo/bin/cargo,cargo)
RUSTFMT := $(if $(wildcard $(HOME)/.cargo/bin/rustfmt),$(HOME)/.cargo/bin/rustfmt,rustfmt)
DOTNET  := $(if $(wildcard $(HOME)/.dotnet/dotnet),$(HOME)/.dotnet/dotnet,dotnet)

.PHONY: help prerequisites contracts contract-test format lint unit coverage build
.PHONY: integration images cluster infra deploy wait run demo e2e chaos diagnostics down destroy clean
.PHONY: format-go format-java format-kotlin format-cpp format-dotnet format-python format-node format-ruby format-rust
.PHONY: lint-go lint-java lint-kotlin lint-cpp lint-dotnet lint-python lint-node lint-ruby lint-rust
.PHONY: unit-go unit-java unit-kotlin unit-cpp unit-dotnet unit-python unit-node unit-ruby unit-rust
.PHONY: coverage-go coverage-java coverage-kotlin coverage-cpp coverage-dotnet coverage-python coverage-node coverage-ruby coverage-rust
.PHONY: build-go build-java build-kotlin build-cpp build-dotnet build-python build-node build-ruby build-rust

help:
	@echo "Rube Goldberg Hello World — make targets"
	@echo ""
	@echo "Milestone 0 (implemented):"
	@echo "  prerequisites   check toolchains and prepare language dependencies"
	@echo "  format          format all languages"
	@echo "  lint            lint all languages"
	@echo "  contracts       validate contract specs parse correctly"
	@echo "  contract-test   validate examples + prohibited-field tests"
	@echo "  unit            run all unit + contract tests"
	@echo "  coverage        unit tests + 90% coverage gates per language"
	@echo "  build           compile all skeleton services"
	@echo "  integration     cross-language artifact integration tests"
	@echo "  e2e             full milestone acceptance (gates + integration)"
	@echo "  clean           remove local build outputs"
	@echo ""
	@echo "Later milestones (stubs):"
	@echo "  images cluster infra deploy wait run demo"
	@echo "  chaos diagnostics down destroy"

# ---------------------------------------------------------------------------
# Guards and helpers
# ---------------------------------------------------------------------------

# $(call guard_tool,command,label) — skip unless STRICT=1, then fail.
define guard_tool
	@command -v $(1) >/dev/null 2>&1 || { \
		echo "SKIP: $(2) not installed$(if $(STRICT), -> FAIL (STRICT=1))"; \
		if [ -n "$(STRICT)" ]; then exit 1; else exit 0; fi; \
	}
endef

# $(call guard_file,path,label) — skip unless STRICT=1, then fail.
define guard_file
	@if [ ! -e $(1) ]; then \
		echo "SKIP: $(2) missing$(if $(STRICT), -> FAIL (STRICT=1))"; \
		if [ -n "$(STRICT)" ]; then exit 1; else exit 0; fi; \
	fi
endef

# $(call guard_librdkafka) — dev headers for the C++ geometry engine.
# -e checks each candidate path because Homebrew include dirs are symlinks
# (find does not follow them) and ls fails when any candidate is missing.
define guard_librdkafka
	@if [ ! -e /opt/homebrew/include/librdkafka/rdkafka.h ] && \
	    [ ! -e /usr/local/include/librdkafka/rdkafka.h ] && \
	    [ ! -e /usr/include/librdkafka/rdkafka.h ]; then \
		echo "SKIP: librdkafka dev headers not found$(if $(STRICT), -> FAIL (STRICT=1))"; \
		if [ -n "$(STRICT)" ]; then exit 1; else exit 0; fi; \
	fi
endef

# $(call gradlew_task,args,label)
define gradlew_task
	$(call guard_file,$(KOTLIN_DIR)/gradlew,Gradle wrapper)
	@echo ">> gradlew $(1) ($(KOTLIN_DIR))"
	cd $(KOTLIN_DIR) && ./gradlew --console=plain -q $(1)
endef

# $(call node_task,args,label) — run for every Node.js service.
define node_task
	@for d in $(NODE_DIRS); do \
		if [ ! -d $$d/node_modules ]; then \
			echo "SKIP: $$d dependencies missing (run 'make prerequisites')$(if $(STRICT), -> FAIL (STRICT=1))"; \
			if [ -n "$(STRICT)" ]; then exit 1; fi; \
		else \
			echo ">> $(2) ($$d)"; \
			(cd $$d && npm run $(1)) || exit 1; \
		fi; \
	done
endef

# $(call cargo_task,args,label)
define cargo_task
	$(call guard_tool,$(CARGO),Cargo)
	@echo ">> cargo $(1) ($(RUST_DIR))"
	cd $(RUST_DIR) && $(CARGO) $(1)
endef

# ---------------------------------------------------------------------------
# Milestone 0 — implemented targets
# ---------------------------------------------------------------------------

prerequisites:
	@bash scripts/prerequisites.sh

contracts:
	@echo ">> Validating contract specs parse correctly"
	$(call guard_tool,python3,Python 3)
	@if [ -x $(VENV)/bin/python3 ]; then \
		$(VENV)/bin/python3 scripts/validate_contracts.py --contracts-only; \
	elif command -v python3 >/dev/null 2>&1; then \
		PYTHONPATH=scripts python3 scripts/validate_contracts.py --contracts-only; \
	else \
		echo "ERROR: python3 not found"; exit 1; \
	fi
	@bash scripts/gen-proto.sh
	@bash scripts/gen-csharp-proto.sh

proto-gen:
	@bash scripts/gen-proto.sh

proto-gen-check:
	@bash scripts/gen-proto.sh --check

contract-test:
	@echo ">> Contract tests: schema validation, example validation, prohibited-field tests"
	$(call guard_tool,python3,Python 3)
	@if [ -x $(VENV)/bin/python3 ]; then \
		$(VENV)/bin/python3 scripts/validate_contracts.py; \
	elif command -v python3 >/dev/null 2>&1; then \
		PYTHONPATH=scripts python3 scripts/validate_contracts.py; \
	else \
		echo "ERROR: python3 not found"; exit 1; \
	fi

format: format-go format-java format-kotlin format-cpp format-dotnet format-python format-node format-ruby format-rust

format-go:
	@for d in $(GO_CLI_DIR) $(GO_NORM_DIR); do \
		echo ">> gofmt -w ($$d)"; \
		(cd $$d && gofmt -w .) || exit 1; \
	done

format-java:
	$(call guard_tool,mvn,Apache Maven)
	@echo ">> spotless:apply ($(JAVA_DIR))"
	cd $(JAVA_DIR) && mvn -q -B spotless:apply

format-kotlin:
	$(call gradlew_task,ktlintFormat,ktlint format)

format-cpp:
	$(call guard_tool,clang-format,clang-format)
	@echo ">> clang-format -i ($(CPP_DIR))"
	clang-format -i $(CPP_DIR)/src/*.cpp $(CPP_DIR)/include/geometry_engine/*.hpp $(CPP_DIR)/tests/*.cpp

format-dotnet:
	$(call guard_tool,$(DOTNET),dotnet)
	@echo ">> dotnet format whitespace ($(DOTNET_DIR))"
	$(DOTNET) format whitespace $(DOTNET_DIR)/rasterizer.csproj
	$(DOTNET) format whitespace $(DOTNET_DIR)/cli/rasterizer.Cli.csproj
	$(DOTNET) format whitespace $(DOTNET_DIR)/rasterizer.Tests/rasterizer.Tests.csproj

format-python:
	@if [ -x $(VENV)/bin/ruff ]; then RUFF="$(VENV)/bin/ruff"; \
	elif command -v ruff >/dev/null 2>&1; then RUFF=ruff; \
	else \
		echo "SKIP: ruff not installed$(if $(STRICT), -> FAIL (STRICT=1))"; \
		if [ -n "$(STRICT)" ]; then exit 1; else exit 0; fi; \
	fi; \
	echo ">> ruff format ($(PYTHON_DIR))"; \
	$$RUFF format $(PYTHON_DIR)

format-node:
	@$(call node_task,format,prettier --write)

format-ruby:
	$(call guard_tool,bundle,Bundler)
	@for d in $(RUBY_DIRS); do \
		echo ">> rubocop -A ($$d)"; \
		(cd $$d && bundle exec rubocop -A) || exit 1; \
	done

format-rust:
	$(call guard_tool,$(RUSTFMT),rustfmt)
	@echo ">> cargo fmt ($(RUST_DIR))"
	cd $(RUST_DIR) && $(CARGO) fmt

lint: lint-go lint-java lint-kotlin lint-cpp lint-dotnet lint-python lint-node lint-ruby lint-rust

lint-go:
	@for d in $(GO_CLI_DIR) $(GO_NORM_DIR); do \
		echo ">> go vet ($$d)"; \
		(cd $$d && go vet ./...) || exit 1; \
		echo ">> gofmt check ($$d)"; \
		(cd $$d && test -z "$$(gofmt -l .)" || { echo "gofmt required:"; gofmt -l .; exit 1; }) || exit 1; \
	done

lint-java:
	$(call guard_tool,mvn,Apache Maven)
	@echo ">> spotless:check ($(JAVA_DIR))"
	cd $(JAVA_DIR) && mvn -q -B spotless:check

lint-kotlin:
	$(call gradlew_task,ktlintCheck,ktlint check)

lint-cpp:
	$(call guard_tool,clang-format,clang-format)
	@echo ">> clang-format --dry-run --Werror ($(CPP_DIR))"
	clang-format --dry-run --Werror $(CPP_DIR)/src/*.cpp $(CPP_DIR)/include/geometry_engine/*.hpp $(CPP_DIR)/tests/*.cpp

lint-dotnet:
	$(call guard_tool,$(DOTNET),dotnet)
	@echo ">> dotnet format --verify-no-changes ($(DOTNET_DIR))"
	$(DOTNET) format --verify-no-changes $(DOTNET_DIR)/rasterizer.csproj
	$(DOTNET) format --verify-no-changes $(DOTNET_DIR)/cli/rasterizer.Cli.csproj
	$(DOTNET) format --verify-no-changes $(DOTNET_DIR)/rasterizer.Tests/rasterizer.Tests.csproj

lint-python:
	@if [ -x $(VENV)/bin/ruff ]; then RUFF="$(VENV)/bin/ruff"; \
	elif command -v ruff >/dev/null 2>&1; then RUFF=ruff; \
	else \
		echo "SKIP: ruff not installed$(if $(STRICT), -> FAIL (STRICT=1))"; \
		if [ -n "$(STRICT)" ]; then exit 1; else exit 0; fi; \
	fi; \
	echo ">> ruff check ($(PYTHON_DIR))"; \
	$$RUFF check $(PYTHON_DIR); \
	echo ">> ruff format --check ($(PYTHON_DIR))"; \
	$$RUFF format --check $(PYTHON_DIR)

lint-node:
	@$(call node_task,lint,prettier --check + typecheck)

lint-ruby:
	$(call guard_tool,bundle,Bundler)
	@for d in $(RUBY_DIRS); do \
		echo ">> rubocop ($$d)"; \
		(cd $$d && bundle exec rubocop) || exit 1; \
	done

lint-rust:
	$(call guard_tool,$(CARGO),Cargo)
	@echo ">> cargo fmt --check ($(RUST_DIR))"
	cd $(RUST_DIR) && $(CARGO) fmt --check
	@echo ">> cargo clippy -D warnings ($(RUST_DIR))"
	cd $(RUST_DIR) && $(CARGO) clippy --all-targets -- -D warnings

coverage: contract-test coverage-go coverage-java coverage-kotlin coverage-cpp coverage-dotnet coverage-python coverage-node coverage-ruby coverage-rust

coverage-go:
	@for d in $(GO_CLI_DIR) $(GO_NORM_DIR); do \
		echo ">> go test -cover ($$d)"; \
		( cd $$d && rm -f out/coverage.out out/coverage.child.out out/coverage.merged.out && mkdir -p out && \
		  PACKAGES="$$(go list ./... | grep -v '/internal/rasterproto$$')" && \
		  RGHELLO_CHILD_COVER="$$PWD/out/coverage.child.out" go test -count=1 -coverprofile=out/coverage.out $$PACKAGES >/dev/null && \
		  head -1 out/coverage.out > out/coverage.merged.out && \
		  grep -h -v '^mode:' out/coverage.out out/coverage.child.out | \
		    awk '{key=$$1" "$$2; if (!(key in cnt)) {span[key]=$$1" "$$2} cnt[key]+=$$3} END {for (k in span) print span[k], cnt[k]}' | \
		    sort >> out/coverage.merged.out && \
		  go tool cover -func=out/coverage.merged.out | \
		    awk '/^total:/ { print "  coverage: " $$3; if ($$3+0 < 90) { print "  FAIL: below 90%"; exit 1 } }' ) || exit 1; \
	done

coverage-java:
	$(call guard_tool,mvn,Apache Maven)
	@echo ">> mvn verify (JaCoCo 90% gate) ($(JAVA_DIR))"
	cd $(JAVA_DIR) && mvn -q -B verify

coverage-kotlin:
	$(call gradlew_task,jacocoTestCoverageVerification,jacoco 90% gate)

coverage-cpp:
	$(call guard_librdkafka)
	@command -v gcovr >/dev/null 2>&1 || { echo "SKIP: gcovr not installed (CI enforces C++ coverage)"; exit 0; }; \
	if ! command -v g++ >/dev/null 2>&1; then echo "SKIP: GNU g++ required for C++ coverage (CI enforces)"; exit 0; fi; \
	echo ">> ctest + gcovr (90% line gate) ($(CPP_DIR))"; \
	cmake -S $(CPP_DIR) -B $(CPP_BUILD) -DCMAKE_BUILD_TYPE=Debug -DENABLE_COVERAGE=ON >/dev/null && \
	cmake --build $(CPP_BUILD) >/dev/null && \
	ctest --test-dir $(CPP_BUILD) --output-on-failure >/dev/null && \
	cd $(CPP_DIR) && gcovr --root . --object-directory "$(abspath $(CPP_BUILD))" \
	  --filter 'src/.*' --filter 'include/.*' --exclude 'src/kafka.cpp' --fail-under-line 90

coverage-dotnet:
	$(call guard_tool,$(DOTNET),dotnet)
	@echo ">> dotnet test with coverlet 90% gate ($(DOTNET_DIR))"
	cd $(DOTNET_DIR)/rasterizer.Tests && $(DOTNET) test --nologo --verbosity quiet /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:Threshold=90 /p:CoverletOutput=coverage/

coverage-python:
	@if [ -x $(VENV)/bin/coverage ]; then COV="$(CURDIR)/$(VENV)/bin/coverage"; \
	elif command -v coverage >/dev/null 2>&1; then COV=coverage; \
	else echo "SKIP: coverage.py not installed (run 'make prerequisites')"; exit 0; fi; \
	echo ">> coverage report (fail-under 90) ($(PYTHON_DIR))"; \
	cd $(PYTHON_DIR) && PYTHONPATH=src $$COV run -m unittest discover -s tests >/dev/null && $$COV report --fail-under=90

coverage-node:
	@$(call node_task,coverage,c8 coverage)

coverage-ruby:
	$(call guard_tool,bundle,Bundler)
	@for d in $(RUBY_DIRS); do \
		echo ">> simplecov rake coverage ($$d)"; \
		(cd $$d && bundle exec rake coverage) || exit 1; \
	done

coverage-rust:
	@if command -v cargo-llvm-cov >/dev/null 2>&1; then \
		echo ">> cargo llvm-cov (90% line gate) ($(RUST_DIR))"; \
		cd $(RUST_DIR) && cargo llvm-cov --lib --fail-under-lines 90; \
	else \
		echo "SKIP: cargo-llvm-cov not installed (CI enforces Rust coverage)"; \
		exit 0; \
	fi

unit: contract-test unit-go unit-java unit-kotlin unit-cpp unit-dotnet unit-python unit-node unit-ruby unit-rust

unit-go:
	@for d in $(GO_CLI_DIR) $(GO_NORM_DIR); do \
		echo ">> go test ($$d)"; \
		(cd $$d && go test ./...) || exit 1; \
	done

unit-java:
	$(call guard_tool,mvn,Apache Maven)
	@echo ">> mvn test ($(JAVA_DIR))"
	cd $(JAVA_DIR) && mvn -q -B test

unit-kotlin:
	$(call gradlew_task,test,gradle test)

unit-cpp:
	$(call guard_tool,cmake,CMake)
	$(call guard_librdkafka)
	@echo ">> cmake + ctest ($(CPP_DIR))"
	cmake -S $(CPP_DIR) -B $(CPP_BUILD) -DCMAKE_BUILD_TYPE=Release >/dev/null
	cmake --build $(CPP_BUILD) >/dev/null
	ctest --test-dir $(CPP_BUILD) --output-on-failure

unit-dotnet:
	$(call guard_tool,$(DOTNET),dotnet)
	@echo ">> dotnet test ($(DOTNET_DIR))"
	cd $(DOTNET_DIR)/rasterizer.Tests && $(DOTNET) test --nologo --verbosity quiet
	cd $(DOTNET_DIR) && $(DOTNET) test --nologo --verbosity quiet

unit-python:
	$(call guard_tool,python3,Python 3)
	@echo ">> unittest ($(PYTHON_DIR))"
	cd $(PYTHON_DIR) && PYTHONPATH=src $(VENV)/bin/python3 -m unittest discover -s tests -v

unit-node:
	@$(call node_task,test,node --test)

unit-ruby:
	$(call guard_tool,ruby,Ruby)
	@for d in $(RUBY_DIRS); do \
		echo ">> minitest ($$d)"; \
		(cd $$d && for f in test/*_test.rb; do ruby -Ilib -Itest "$$f"; done) || exit 1; \
	done

unit-rust:
	$(call cargo_task,test,cargo test)

build: build-go build-java build-kotlin build-cpp build-dotnet build-python build-node build-ruby build-rust

build-go:
	@for d in $(GO_CLI_DIR) $(GO_NORM_DIR); do \
		echo ">> go build ($$d)"; \
		(cd $$d && go build ./...) || exit 1; \
	done

build-java:
	$(call guard_tool,mvn,Apache Maven)
	@echo ">> mvn package -DskipTests ($(JAVA_DIR))"
	cd $(JAVA_DIR) && mvn -q -B -DskipTests package

build-kotlin:
	$(call gradlew_task,assemble,gradle assemble)

build-cpp:
	$(call guard_tool,cmake,CMake)
	$(call guard_librdkafka)
	@echo ">> cmake --build ($(CPP_DIR))"
	cmake -S $(CPP_DIR) -B $(CPP_BUILD) -DCMAKE_BUILD_TYPE=Release >/dev/null
	cmake --build $(CPP_BUILD)

build-dotnet:
	$(call guard_tool,$(DOTNET),dotnet)
	@echo ">> dotnet build ($(DOTNET_DIR))"
	$(DOTNET) build --nologo --verbosity quiet $(DOTNET_DIR)/cli/rasterizer.Cli.csproj
	$(DOTNET) build --nologo --verbosity quiet $(DOTNET_DIR)/rasterizer.Tests/rasterizer.Tests.csproj

build-python:
	$(call guard_tool,python3,Python 3)
	@echo ">> python compileall ($(PYTHON_DIR))"
	cd $(PYTHON_DIR) && python3 -m compileall -q src

build-node:
	@$(call node_task,build,tsc build)

build-ruby:
	@echo ">> ruby syntax check ($(RUBY_DIRS))"
	@for d in $(RUBY_DIRS); do \
		echo ">> ruby syntax check ($$d)"; \
		(cd $$d && for f in $$(ls lib/*.rb); do ruby -c "$$f"; done) || exit 1; \
	done

build-rust:
	$(call cargo_task,build,cargo build)

clean:
	@rm -rf $(BUILD_DIR)
	@cd $(KOTLIN_DIR) && rm -rf build .kotlin 2>/dev/null || true
	@cd $(JAVA_DIR) && mvn -q clean 2>/dev/null || true
	@cd $(DOTNET_DIR) && rm -rf bin obj 2>/dev/null || true
	@cd $(RUST_DIR) && $(CARGO) clean 2>/dev/null || true
	@for d in $(NODE_DIRS); do rm -rf $$d/out 2>/dev/null || true; done
	@find $(PYTHON_DIR) -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "clean: done"

# ---------------------------------------------------------------------------
# Later milestones — defined here so the interface exists.
# ---------------------------------------------------------------------------

integration:
	@bash tests/integration/run_integration.sh

images:
	@bash scripts/build-images.sh

cluster:
	@bash scripts/k3d-create.sh

infra:
	cd infra/terraform/environments/local && terraform init && terraform apply -auto-approve

deploy:
	@bash scripts/deploy.sh

wait:
	@bash scripts/wait-ready.sh

run:
	@cd cmd/rghw && go run . run --api-url "http://localhost:8080"

demo: wait
	@bash scripts/smoke-test.sh

e2e:
	@bash tests/end-to-end/run_e2e.sh

chaos:
	@bash tests/chaos/chaos.sh

diagnostics:
	@bash scripts/collect-diagnostics.sh

low-memory:
	@bash scripts/low-memory-profile.sh

down:
	@bash scripts/k3d-delete.sh

destroy:
	cd infra/terraform/environments/local && terraform destroy -auto-approve
