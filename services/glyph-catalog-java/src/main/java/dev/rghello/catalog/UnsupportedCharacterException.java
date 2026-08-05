package dev.rghello.catalog;

import org.springframework.ws.soap.server.endpoint.annotation.FaultCode;
import org.springframework.ws.soap.server.endpoint.annotation.SoapFault;

@SoapFault(faultCode = FaultCode.CLIENT, faultStringOrReason = "UnsupportedCharacter")
public class UnsupportedCharacterException extends RuntimeException {

  public UnsupportedCharacterException(String codePoint) {
    super("Unsupported character " + codePoint + " in alphabet " + GlyphDefinitions.ALPHABET);
  }
}
