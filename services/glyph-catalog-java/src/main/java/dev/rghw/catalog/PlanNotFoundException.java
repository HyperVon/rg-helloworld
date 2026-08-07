package dev.rghw.catalog;

import org.springframework.ws.soap.server.endpoint.annotation.FaultCode;
import org.springframework.ws.soap.server.endpoint.annotation.SoapFault;

@SoapFault(faultCode = FaultCode.CLIENT, faultStringOrReason = "PlanNotFound")
public class PlanNotFoundException extends RuntimeException {

  public PlanNotFoundException(String planId) {
    super("No plan with id " + planId);
  }
}
