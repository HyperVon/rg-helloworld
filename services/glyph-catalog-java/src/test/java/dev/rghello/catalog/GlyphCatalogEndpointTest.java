package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertTrue;

import dev.rghello.catalog.contract.PlanPhraseResponse;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.ws.test.server.MockWebServiceClient;
import org.springframework.ws.test.server.RequestCreators;
import org.springframework.ws.test.server.ResponseMatchers;
import org.springframework.xml.transform.StringSource;

@SpringBootTest(
    properties = {
      "spring.datasource.url=jdbc:h2:mem:endpoint;DB_CLOSE_DELAY=-1",
      "spring.main.web-application-type=none",
    })
class GlyphCatalogEndpointTest {

  private static final String NAMESPACE = "urn:rube-goldberg:glyph-catalog:v1";
  private static final Map<String, String> NAMESPACES = Map.of("glyph", NAMESPACE);

  @Autowired private ApplicationContext context;

  @Autowired private GlyphCatalogService service;

  private MockWebServiceClient client;

  @BeforeEach
  void setUp() {
    client = MockWebServiceClient.createClient(context);
  }

  @Test
  void planPhraseReturnsElevenOrderedGlyphs() {
    client
        .sendRequest(
            RequestCreators.withPayload(
                payload(withNamespace(planPhrase("Hello World", "PRIMARY")))))
        .andExpect(ResponseMatchers.noFault())
        .andExpect(
            ResponseMatchers.xpath(
                    "count(/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph)", NAMESPACES)
                .evaluatesTo("11"))
        .andExpect(
            ResponseMatchers.xpath(
                    "/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph[6]/glyph:kind", NAMESPACES)
                .evaluatesTo("GAP"))
        .andExpect(
            ResponseMatchers.xpath(
                    "/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph[6]/glyph:advanceWidth",
                    NAMESPACES)
                .evaluatesTo("0.6"))
        .andExpect(
            ResponseMatchers.xpath(
                    "count(/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph[1]/"
                        + "glyph:primitives/glyph:primitive)",
                    NAMESPACES)
                .evaluatesTo("3"));
  }

  @Test
  void planPhraseWithoutVariantDefaultsToPrimary() {
    client
        .sendRequest(RequestCreators.withPayload(payload(withNamespace(planPhrase("Hello", null)))))
        .andExpect(ResponseMatchers.noFault())
        .andExpect(
            ResponseMatchers.xpath(
                    "count(/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph)", NAMESPACES)
                .evaluatesTo("5"));
  }

  @Test
  void unsupportedCharacterProducesSoapFault() {
    client
        .sendRequest(
            RequestCreators.withPayload(
                payload(withNamespace(planPhrase("Hello World!", "PRIMARY")))))
        .andExpect(ResponseMatchers.clientOrSenderFault());
  }

  @Test
  void unknownPlanProducesSoapFault() {
    client
        .sendRequest(
            RequestCreators.withPayload(
                payload(
                    withNamespace(
                        "<glyph:GetAlternateBlueprintRequest>"
                            + "<glyph:planId>00000000-0000-0000-0000-000000000000</glyph:planId>"
                            + "<glyph:glyphInstanceId>missing</glyph:glyphInstanceId>"
                            + "<glyph:excludedVariant>PRIMARY</glyph:excludedVariant>"
                            + "</glyph:GetAlternateBlueprintRequest>"))))
        .andExpect(ResponseMatchers.clientOrSenderFault());
  }

  @Test
  void getAlternateBlueprintReturnsSingleAlternateGlyph() {
    PlanPhraseResponse plan = service.planPhrase("Hello", "RUBE_SIMPLEX_V1", "PRIMARY");
    String glyphInstanceId = plan.getGlyphs().getGlyph().get(0).getGlyphInstanceId();

    client
        .sendRequest(
            RequestCreators.withPayload(
                payload(
                    withNamespace(
                        ("<glyph:GetAlternateBlueprintRequest>"
                                + "<glyph:planId>%s</glyph:planId>"
                                + "<glyph:glyphInstanceId>%s</glyph:glyphInstanceId>"
                                + "<glyph:excludedVariant>PRIMARY</glyph:excludedVariant>"
                                + "</glyph:GetAlternateBlueprintRequest>")
                            .formatted(plan.getPlanId(), glyphInstanceId)))))
        .andExpect(ResponseMatchers.noFault())
        .andExpect(
            ResponseMatchers.xpath(
                    "count(/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph)", NAMESPACES)
                .evaluatesTo("1"))
        .andExpect(
            ResponseMatchers.xpath(
                    "/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph[1]/glyph:position",
                    NAMESPACES)
                .evaluatesTo("0"))
        .andExpect(
            ResponseMatchers.xpath(
                    "/glyph:PlanPhraseResponse/glyph:glyphs/glyph:glyph[1]/"
                        + "glyph:glyphInstanceId",
                    NAMESPACES)
                .evaluatesTo(glyphInstanceId));
  }

  @Test
  void wsdlDefinitionExists() {
    assertTrue(
        context.containsBean("glyph-catalog"),
        "SimpleWsdl11Definition bean 'glyph-catalog' must exist");
  }

  private static String planPhrase(String message, String variant) {
    return ("<glyph:PlanPhraseRequest>"
            + "<glyph:message>%s</glyph:message>"
            + "<glyph:alphabet>RUBE_SIMPLEX_V1</glyph:alphabet>"
            + (variant == null ? "" : "<glyph:variant>%s</glyph:variant>")
            + "</glyph:PlanPhraseRequest>")
        .formatted(message, variant);
  }

  private static StringSource payload(String body) {
    return new StringSource(body);
  }

  private static String withNamespace(String body) {
    return body.replaceFirst(">", " xmlns:glyph=\"" + NAMESPACE + "\">");
  }
}
