package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest(
    properties = {
      "spring.datasource.url=jdbc:h2:mem:context;DB_CLOSE_DELAY=-1",
      "spring.main.web-application-type=none",
    })
class GlyphCatalogContextTest {

  @Autowired private JdbcTemplate jdbc;

  @Autowired private PhrasePlanner planner;

  @Autowired private GlyphCatalogService service;

  @Test
  void contextLoads() {
    assertNotNull(jdbc);
    assertNotNull(planner);
    assertNotNull(service);
  }

  @Test
  void schemaInitialized() {
    Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM glyph_plans", Integer.class);
    assertEquals(0, count);
  }
}
