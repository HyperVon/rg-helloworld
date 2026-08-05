package dev.rghello.catalog;

import dev.rghello.catalog.contract.GetAlternateBlueprintRequest;
import dev.rghello.catalog.contract.ObjectFactory;
import dev.rghello.catalog.contract.PlanPhraseRequest;
import dev.rghello.catalog.contract.PlanPhraseResponse;
import jakarta.xml.bind.JAXBElement;
import org.springframework.ws.server.endpoint.annotation.Endpoint;
import org.springframework.ws.server.endpoint.annotation.PayloadRoot;
import org.springframework.ws.server.endpoint.annotation.RequestPayload;
import org.springframework.ws.server.endpoint.annotation.ResponsePayload;

@Endpoint
public class GlyphCatalogEndpoint {

  public static final String NAMESPACE = "urn:rube-goldberg:glyph-catalog:v1";

  private final GlyphCatalogService service;
  private final ObjectFactory objectFactory = new ObjectFactory();

  public GlyphCatalogEndpoint(GlyphCatalogService service) {
    this.service = service;
  }

  @PayloadRoot(namespace = NAMESPACE, localPart = "PlanPhraseRequest")
  @ResponsePayload
  public JAXBElement<PlanPhraseResponse> planPhrase(
      @RequestPayload JAXBElement<PlanPhraseRequest> request) {
    PlanPhraseRequest body = request.getValue();
    String variant = body.getVariant() != null ? body.getVariant() : "PRIMARY";
    PlanPhraseResponse response =
        service.planPhrase(body.getMessage(), body.getAlphabet(), variant);
    return objectFactory.createPlanPhraseResponse(response);
  }

  @PayloadRoot(namespace = NAMESPACE, localPart = "GetAlternateBlueprintRequest")
  @ResponsePayload
  public JAXBElement<PlanPhraseResponse> getAlternateBlueprint(
      @RequestPayload JAXBElement<GetAlternateBlueprintRequest> request) {
    GetAlternateBlueprintRequest body = request.getValue();
    PlanPhraseResponse response =
        service.getAlternateBlueprint(
            body.getPlanId(), body.getGlyphInstanceId(), body.getExcludedVariant());
    return objectFactory.createPlanPhraseResponse(response);
  }
}
