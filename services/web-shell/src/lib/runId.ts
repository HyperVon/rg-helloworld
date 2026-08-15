const RUN_ID_PATTERN =
  /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

export function isValidRunId(value: string | null | undefined): value is string {
  return typeof value === 'string' && RUN_ID_PATTERN.test(value);
}

export function sanitizeRunId(value: string | null | undefined): string | null {
  return isValidRunId(value) ? value : null;
}
