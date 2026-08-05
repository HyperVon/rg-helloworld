package dev.rghello.catalog;

import org.springframework.ws.soap.server.endpoint.annotation.FaultCode;
import org.springframework.ws.soap.server.endpoint.annotation.SoapFault;

@SoapFault(faultCode = FaultCode.CLIENT, faultStringOrReason = "UnsupportedAlphabet")
public class UnsupportedAlphabetException extends RuntimeException {

  public UnsupportedAlphabetException(String alphabet) {
    super("Unsupported alphabet " + alphabet);
  }
}
