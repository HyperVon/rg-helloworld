---
name: threat-modeling
description: >-
  Build a repository-grounded threat model for an application, service, API,
  agent workflow, or architecture by mapping assets, actors, trust boundaries,
  entrypoints, attacker capabilities, abuse paths, and mitigations. Use only
  for explicit threat-model, attack-surface, DFD, STRIDE, PASTA, LINDDUN, or
  abuse-path requests; use security-review for ordinary vulnerability review.
  Report by default and do not probe external systems.
---

# Threat Modeling

## Contract

- **Input:** repository or system scope, deployment and exposure assumptions,
  actors, assets, known components, and the user's authorized review level.
- **Output:** a concise threat model containing system boundaries, assets,
  attacker capabilities and non-capabilities, realistic abuse paths,
  likelihood/impact reasoning, existing and recommended mitigations,
  assumptions, questions, and coverage gaps.
- **Owner:** design-time security modeling and abuse-path analysis.
- **Non-goals:** unrestricted penetration testing, live exploit traffic,
  compliance certification, incident response, or a substitute for a focused
  `security-review` of an implementation.
- **Side effects:** read-only by default; do not contact external systems,
  access credentials, or modify files without separate explicit authority.

## Threat categorization and AI vectors

Apply **STRIDE** systematically across every identified trust boundary:

- **S**poofing: Impersonating users, services, webhook senders, or agent identities.
- **T**ampering: Modifying payloads in transit, poisoning cache/persistence, or tampering with model context and prompt templates.
- **R**epudiation: Performing sensitive or destructive actions without immutable audit logs.
- **I**nformation Disclosure: Exposing credentials, PII, cross-tenant data, internal stack traces, or system prompts.
- **D**enial of Service: Exhausting API rate limits, computational budgets, worker memory, or token context windows.
- **E**levation of Privilege: Escaping container/sandbox boundaries, escalating API roles, or executing unauthorized agent tools.

For **AI and Agentic Workflows**, explicitly evaluate:

1. *Indirect Prompt Injection:* Untrusted inputs (user tickets, scraped web pages, third-party files) overriding agent instructions.
2. *Tool Privilege Escalation & Confused Deputy:* Agent executing destructive tools (file writes, shell execution, database mutations) on behalf of unauthenticated or unauthorized inputs.
3. *Data Exfiltration via Rendered Output:* Leaking sensitive context via markdown image URLs, webhooks, or automated outbound network requests.
4. *Context & Skill Poisoning:* Malicious external skills, untrusted repository rules, or poisoned prompt fixtures compromising agent invariants.

## Workflow

1. **Confirm the explicit trigger and scope.** Identify the requested path,
   deployment model, internet exposure, authentication expectations, and data
   sensitivity. Ask only the questions that materially change threat ranking;
   preserve unresolved assumptions if the user cannot answer.
2. **Extract the system model from evidence.** Identify components, entrypoints,
   data stores, external integrations, runtime versus CI/dev/test tooling, and
   source-of-truth architecture. Do not claim a component or control from a
   filename or generic framework expectation.
3. **Map boundaries and assets.** Record concrete edges between components with
   protocol, identity, encryption, validation, rate-limit, or serialization
   details. Identify credentials, sensitive data, integrity-critical state,
   availability-critical resources, build artifacts, and audit records.
4. **Calibrate attackers.** Describe realistic capabilities based on exposure,
   tenancy, deployment, and access assumptions. Explicitly record important
   non-capabilities to avoid inflated severity.
5. **Enumerate and prioritize abuse paths.** Tie each threat to an attacker
   goal, boundary, asset, precondition, and impact. Keep the set small and
   high quality; rank likelihood and impact with short evidence-backed reasons.
6. **Recommend and check coverage.** Distinguish existing controls from
   recommendations and tie each mitigation to a component, boundary, or
   entrypoint. Confirm that every discovered boundary and entrypoint is
   represented, or state why it is out of scope.
7. **Report and stop.** State assumptions, unanswered questions, threats,
   evidence, mitigations, and residual risk. Stop before live probing,
   credentialed testing, destructive activity, or implementation unless the
   user separately authorizes it.

## Threat model report template

Format the report with the following sections and tables. Use the exact
heading structure; populate each table with findings from the analysis:

### 1. System decomposition & trust boundaries

| Boundary ID | Source Component | Target Component | Protocol / Transport | Auth / Trust Level |
| :--- | :--- | :--- | :--- | :--- |

### 2. Attacker profiles & capabilities

| Persona | Access Level | Motive & Capabilities | Explicit Non-Capabilities |
| :--- | :--- | :--- | :--- |

### 3. Prioritized abuse paths

| Threat ID | STRIDE Category | Trust Boundary | Preconditions | Abuse Path & Impact | Likelihood | Existing Control | Recommended Mitigation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |

### 4. Residual risks, assumptions, & unverified areas

- **Assumptions:** List critical deployment/environmental assumptions.
- **Coverage gaps:** List uninspected components or missing documentation.

## Routing boundaries

- Use `security-review` for a concrete code/configuration change or suspected
  vulnerability and for safe local exploitability checks.
- Use `architecture-review` for non-security redesign options; combine only
  when the user requests both architecture and threat modeling.
- Use `quality-hardening` for security regression tests after the model, not as
  a replacement for modeling.

Never label a system secure because the threat list is short or static checks
are clean. Keep observations, assumptions, inferences, and unknowns separate.
