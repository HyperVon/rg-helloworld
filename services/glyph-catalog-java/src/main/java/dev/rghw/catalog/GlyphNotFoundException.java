package dev.rghw.catalog;

import org.springframework.ws.soap.server.endpoint.annotation.FaultCode;
import org.springframework.ws.soap.server.endpoint.annotation.SoapFault;

@SoapFault(faultCode = FaultCode.CLIENT, faultStringOrReason = "GlyphNotFound")
public class GlyphNotFoundException extends RuntimeException {

  public GlyphNotFoundException(String glyphInstanceId) {
    super("No glyph " + glyphInstanceId + " in plan");
  }
}
