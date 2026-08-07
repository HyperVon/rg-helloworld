package dev.rghw.catalog;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

  @GetMapping("/healthz")
  public String healthz() {
    return "OK";
  }
}
