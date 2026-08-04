package dev.rghello.catalog;

import java.io.PrintStream;
import java.util.function.IntConsumer;

public final class GlyphCatalogApplication {

  public static final String SERVICE_NAME = "glyph-catalog";
  public static final String MILESTONE = "0.0.0-skeleton";

  static IntConsumer exit = System::exit;

  private GlyphCatalogApplication() {}

  public static void main(String[] args) {
    exit.accept(run(System.out, System.err, args));
  }

  static int run(PrintStream out, PrintStream err, String[] args) {
    if (args.length == 1 && "version".equals(args[0])) {
      out.printf("%s %s%n", SERVICE_NAME, GlyphCatalogVersion.VERSION);
      return 0;
    }
    err.printf("%s: Milestone 0 skeleton - functionality not implemented yet%n", SERVICE_NAME);
    err.printf("usage: %s version%n", SERVICE_NAME);
    return 0;
  }
}
