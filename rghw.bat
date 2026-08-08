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
REM   rghw.bat --dry-run    -- print plan
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
if exist cmd\rghw\rghw.exe (
  cmd\rghw\rghw.exe run --api-url http://localhost:8080 --timeout 3m
) else (
  go run ./cmd/rghw run --api-url http://localhost:8080 --timeout 3m || make run
)
echo [rghw] Done. Web UIs remain at http://localhost:3000 etc.
echo [rghw] Stop forwards: taskkill /F /IM kubectl.exe
goto :eof

:dryrun
echo [rghw] Dry run -- would execute:
echo   make prerequisites
echo   make cluster
echo   make images
echo   make infra
echo   make wait
echo   kubectl port-forward x9 (see rghw.sh --help for full list)
echo   rghw run --api-url http://localhost:8080 --timeout 3m
echo.
echo   Web Shell: http://localhost:3000, Grafana: http://localhost:3002, Prometheus: http://localhost:9090
goto :eof

:help
echo rghw.bat -- one-command demo for Rube Goldberg Hello World (Windows)
echo.
echo Usage: rghw.bat [options]
echo   --help, --dry-run, --skip-images, --skip-infra
echo   See rghw.sh --help for full docs and URL table
echo   Prefer Git Bash:  bash rghw.sh
goto :eof
