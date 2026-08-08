@echo off
REM Rube Goldberg Hello World -- one-command demo (Windows)
REM Starts k3d cluster, builds images, applies infra, waits, runs rghw, prints URLs
REM Requires: Docker Desktop, k3d, kubectl, terraform, Go 1.26+, make (Git Bash / WSL)
REM
REM Usage:
REM   rghw.bat              -- full bring-up + run
REM   rghw.bat --help       -- this help
REM   rghw.bat --skip-images-- reuse images
REM   rghw.bat --skip-infra -- skip terraform
REM   rghw.bat --quiet/--silent -- HELLO WORLD only on stdout
REM   rghw.bat --fresh      -- clean previous runs (Redis+MinIO) before bring-up
REM   rghw.bat --dry-run    -- print plan
REM   rghw.bat --timeout 3m -- rghw run timeout
REM   rghw.bat --api-url http://localhost:8080 -- override orchestrator URL
REM
REM Web UIs (after port-forwards):
REM   Web Shell:          http://rghw.localhost/          -> http://localhost:3000
REM   Artifact Inspector: http://rghw.localhost/inspector/ -> http://localhost:3001
REM   Event Gateway:      http://rghw.localhost/api/       -> http://localhost:8081
REM   Grafana:            http://grafana.rghw.localhost/   -> http://localhost:3002
REM   Prometheus:                                        -> http://localhost:9090
REM   Loki:                                              -> http://localhost:3100
REM   Tempo:                                             -> http://localhost:3200
REM   MinIO:              http://minio.rghw.localhost/     -> http://localhost:9000
REM   Orchestrator:       http://rghw.localhost/api/       -> http://localhost:8080

setlocal enabledelayedexpansion

if "%1"=="--help" goto :help
if "%1"=="-h" goto :help
if "%1"=="--dry-run" goto :dryrun

echo [rghw] Rube Goldberg Hello World -- demo (Windows)
echo [rghw] Checking prerequisites...
where docker >nul 2>&1 || echo [warn] docker not found
where k3d >nul 2>&1 || echo [warn] k3d not found
where kubectl >nul 2>&1 || echo [warn] kubectl not found

REM Prefer bash if available (Git Bash / WSL) - delegate to rghw.sh
where bash >nul 2>&1
if %ERRORLEVEL%==0 (
  echo [rghw] Delegating to bash rghw.sh %*
  bash rghw.sh %*
  exit /b %ERRORLEVEL%
)

REM Fallback: direct make calls (requires make in PATH, e.g. via choco or GnuWin)
echo [rghw] bash not found, using make directly...

echo [rghw] make cluster...
make cluster || (echo [error] make cluster failed & exit /b 1)

if not "%1"=="--skip-images" if not "%2"=="--skip-images" (
  echo [rghw] make images...
  make images || (echo [error] make images failed & exit /b 1)
) else (
  echo [rghw] Skipping make images
)

if not "%1"=="--skip-infra" if not "%2"=="--skip-infra" (
  echo [rghw] make infra...
  make infra || (echo [error] make infra failed & exit /b 1)
) else (
  echo [rghw] Skipping make infra
)

echo [rghw] make wait...
make wait || (echo [error] make wait failed & exit /b 1)

echo [rghw] Starting port-forwards (use Git Bash for full URL table)...
start /B kubectl port-forward -n rube-goldberg svc/run-orchestrator 8080:8080 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/web-shell 3000:80 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/event-gateway 8081:8080 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/artifact-inspector 3001:80 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/grafana 3002:3000 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/prometheus 9090:9090 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/loki 3100:3100 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/tempo 3200:3200 >nul 2>&1
start /B kubectl port-forward -n rube-goldberg svc/minio 9000:9000 >nul 2>&1

timeout /t 3 >nul 2>&1

echo.
echo Web URLs -- Rube Goldberg Hello World
echo ================================================================
echo   Web Shell:          http://localhost:3000   (http://rghw.localhost/)
echo   Artifact Inspector: http://localhost:3001   (http://rghw.localhost/inspector/)
echo   Event Gateway:      http://localhost:8081   (http://rghw.localhost/api/)
echo   Grafana:            http://localhost:3002   (http://grafana.rghw.localhost/)
echo   Prometheus:         http://localhost:9090
echo   Loki:               http://localhost:3100
echo   Tempo:              http://localhost:3200
echo   MinIO:              http://localhost:9000   (http://minio.rghw.localhost/)
echo   Orchestrator:       http://localhost:8080   (http://rghw.localhost/api/)
echo ================================================================
echo.

echo [rghw] Running rghw...
REM Honor --quiet/--silent and --fresh even in native fallback (Git Bash path already handles it via delegation)
set RGHW_QUIET=
set RGHW_FRESH=
for %%A in (%*) do (
  if "%%~A"=="--quiet" set RGHW_QUIET=--quiet
  if "%%~A"=="--silent" set RGHW_QUIET=--quiet
  if "%%~A"=="--fresh" set RGHW_FRESH=1
)
if defined RGHW_FRESH (
  echo [rghw] Fresh mode -- lightweight clean (Redis + MinIO, preserving Kafka). Full wipe: make destroy
  kubectl exec -n rube-goldberg redis-master-0 -- redis-cli -a RedisPassw0rd! EVAL "for i,k in ipairs(redis.call('keys','*')) do redis.call('del',k) end return 'ok'" 0 2>nul | findstr ok >nul && echo [rghw] fresh: Redis cleaned || kubectl exec -n rube-goldberg deploy/redis-master -- redis-cli -a RedisPassw0rd! EVAL "for i,k in ipairs(redis.call('keys','*')) do redis.call('del',k) end return 'ok'" 0 2>nul | findstr ok >nul && echo [rghw] fresh: Redis cleaned || echo [warn] fresh: Redis flush skipped
  kubectl exec -n rube-goldberg deploy/minio -- sh -c "mc alias set local http://127.0.0.1:9000 %MINIO_ROOT_USER% %MINIO_ROOT_PASSWORD% >nul 2>&1 && mc rm --recursive --force local/rube-goldberg-artifacts/ 2>nul && echo ok" 2>nul | findstr ok >nul && echo [rghw] fresh: MinIO cleaned || echo [warn] fresh: MinIO clean skipped
  REM No restart: per-runId state, restart forces Kafka rebalance and drops next run's events
)
if exist cmd\rghw\rghw.exe (
  cmd\rghw\rghw.exe run --api-url http://localhost:8080 --timeout 3m %RGHW_QUIET%
) else (
  go run ./cmd/rghw run --api-url http://localhost:8080 --timeout 3m %RGHW_QUIET% || make run
)
echo [rghw] Done. Web UIs remain at http://localhost:3000 etc.
echo [rghw] Stop forwards: taskkill /F /IM kubectl.exe
goto :eof

:dryrun
echo [rghw] Dry run -- would execute:
echo   make prerequisites
echo   make cluster
echo   make images   (unless --skip-images)
echo   make infra    (unless --skip-infra)
echo   make wait
echo   kubectl port-forward x9 (web-shell 3000:80, event-gateway 8081:80, ...)
echo   rghw run --api-url http://localhost:8080 --timeout 3m [--quiet if --quiet] [--fresh cleans Redis+MinIO]
echo.
echo Note: With Git Bash, dry-run delegates to bash rghw.sh --dry-run [--quiet] [--fresh] for exact output.
echo.
echo   Web Shell: http://localhost:3000, Grafana: http://localhost:3002, Prometheus: http://localhost:9090
goto :eof

:help
echo rghw.bat -- one-command demo for Rube Goldberg Hello World (Windows)
echo.
echo Usage: rghw.bat [options]
echo   --help, -h            Show this help
echo   --skip-images       Skip make images
echo   --skip-infra        Skip terraform apply
echo   --quiet, --silent   Only print HELLO WORLD to stdout
echo   --fresh             Clean previous runs (Redis+MinIO, keeps Kafka)
echo   --timeout D         rghw run timeout (default 3m)
echo   --api-url URL       Orchestrator URL (default http://localhost:8080)
echo   --dry-run           Print plan without executing
echo   --open              Open browser tabs after run
echo.
echo See rghw.sh --help for full docs and URL table
echo Prefer Git Bash:  bash rghw.sh --quiet
goto :eof
