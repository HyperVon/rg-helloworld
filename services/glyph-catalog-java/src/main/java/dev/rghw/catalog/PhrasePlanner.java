package dev.rghw.catalog;

import dev.rghw.catalog.contract.Glyph;
import dev.rghw.catalog.contract.Glyphs;
import dev.rghw.catalog.contract.PlanPhraseResponse;
import dev.rghw.catalog.contract.Primitives;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Component;

@Component
public class PhrasePlanner {

  public PlanPhraseResponse plan(String message, String alphabet, String variant) {
    if (!GlyphDefinitions.ALPHABET.equals(alphabet)) {
      throw new UnsupportedAlphabetException(alphabet == null ? "null" : alphabet);
    }
    if (!"PRIMARY".equals(variant)) {
      throw new UnsupportedVariantException(variant == null ? "null" : variant);
    }
    PlanPhraseResponse response = new PlanPhraseResponse();
    response.setPlanId(UUID.randomUUID().toString());
    int[] codePoints = message.codePoints().toArray();
    List<Glyph> glyphs = new ArrayList<>(codePoints.length);
    for (int i = 0; i < codePoints.length; i++) {
      glyphs.add(toGlyph(codePoints[i], i));
    }
    Glyphs wrapper = new Glyphs();
    wrapper.getGlyph().addAll(glyphs);
    response.setGlyphs(wrapper);
    return response;
  }

  private static Glyph toGlyph(int codePoint, int position) {
    Glyph glyph = new Glyph();
    glyph.setGlyphInstanceId(UUID.randomUUID().toString());
    glyph.setPosition(position);
    if (codePoint == ' ') {
      glyph.setKind("GAP");
      glyph.setAdvanceWidth(GlyphDefinitions.GAP_WIDTH);
      glyph.setPrimitives(new Primitives());
      return glyph;
    }
    GlyphDefinitions.GlyphDef definition = GlyphDefinitions.DEFINITIONS.get((char) codePoint);
    if (definition == null) {
      throw new UnsupportedCharacterException(String.format("U+%04X", codePoint));
    }
    glyph.setKind("DRAWABLE");
    glyph.setAdvanceWidth(definition.advanceWidth());
    Primitives primitives = new Primitives();
    primitives.getPrimitive().addAll(GlyphDefinitions.copyPrimitives(definition));
    glyph.setPrimitives(primitives);
    return glyph;
  }
}
