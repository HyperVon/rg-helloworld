package dev.rghello.catalog;

import org.springframework.ws.soap.server.endpoint.annotation.FaultCode;
import org.springframework.ws.soap.server.endpoint.annotation.SoapFault;

@SoapFault(faultCode = FaultCode.CLIENT, faultStringOrReason = "UnsupportedVariant")
public class UnsupportedVariantException extends RuntimeException {

  public UnsupportedVariantException(String variant) {
    super("Unsupported variant " + variant);
  }
}
