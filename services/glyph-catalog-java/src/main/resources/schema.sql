CREATE TABLE IF NOT EXISTS glyph_plans (
  plan_id VARCHAR(36) PRIMARY KEY,
  created_at TIMESTAMP NOT NULL,
  plan_json CLOB NOT NULL
);
