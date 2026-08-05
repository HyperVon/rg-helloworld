package dev.rghello.catalog;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class GlyphCatalogApplication {

  public static final String SERVICE_NAME = "glyph-catalog";
  public static final String MILESTONE = "0.1.0-milestone4";

  private GlyphCatalogApplication() {}

  public static void main(String[] args) {
    if (args.length == 1 && "version".equals(args[0])) {
      System.out.printf("%s %s%n", SERVICE_NAME, GlyphCatalogVersion.VERSION);
      return;
    }
    SpringApplication.run(GlyphCatalogApplication.class, args);
  }
}
