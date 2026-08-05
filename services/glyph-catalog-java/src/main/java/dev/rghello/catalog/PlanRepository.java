package dev.rghello.catalog;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.rghello.catalog.contract.PlanPhraseResponse;
import java.time.Instant;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class PlanRepository {

  private final JdbcTemplate jdbc;
  private final ObjectMapper mapper;

  public PlanRepository(JdbcTemplate jdbc, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.mapper = mapper;
  }

  public void save(PlanPhraseResponse plan) {
    String json;
    try {
      json = mapper.writeValueAsString(plan);
    } catch (JsonProcessingException e) {
      throw new IllegalStateException("Failed to serialize plan " + plan.getPlanId(), e);
    }
    jdbc.update(
        "INSERT INTO glyph_plans (plan_id, created_at, plan_json) VALUES (?, ?, ?)",
        plan.getPlanId(),
        Instant.now(),
        json);
  }

  public PlanPhraseResponse findById(String planId) {
    List<String> rows =
        jdbc.query(
            "SELECT plan_json FROM glyph_plans WHERE plan_id = ?",
            (rs, rowNum) -> rs.getString(1),
            planId);
    if (rows.isEmpty()) {
      return null;
    }
    try {
      return mapper.readValue(rows.get(0), PlanPhraseResponse.class);
    } catch (JsonProcessingException e) {
      throw new IllegalStateException("Failed to deserialize plan " + planId, e);
    }
  }
}
