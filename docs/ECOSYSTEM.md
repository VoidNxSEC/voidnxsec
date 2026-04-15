# The Foundational Ecosystem

Voidnxsec is not just a standalone tool; it is part of a broader, interconnected ecosystem of foundational projects. Together, these projects form a comprehensive suite for secure, verifiable, and AI-augmented systems engineering.

## Core Projects & Interactions

### 1. Voidnxsec & Void Fortress Framework
*   **Role:** The Execution and Orchestration Engine.
*   **Function:** Handles the low-level OS bootstrapping (`void-fortress-framework` in shell/C), state orchestration (Rust/Go), and deterministic phase transitions.
*   **Outputs:** Structured JSONL state events containing cryptographic hashes of system states.

### 2. ADR Ledger (`adr-ledger`)
*   **Role:** The Verifiable State and Decision Ledger.
*   **Function:** Ingests the JSONL events from `voidnxsec` to create an immutable, cryptographically verifiable ledger of every state transition and architectural decision made during a system's lifecycle.
*   **Integration Point:** The Rust/Go orchestration layers in `voidnxsec` act as clients/validators for the `adr-ledger`.

### 3. SecureLLM MCP (`securellm-mcp`)
*   **Role:** The AI Augmentation and Security Interface.
*   **Function:** A Model Context Protocol (MCP) server that allows AI models (like LLMs) to securely interact with the ecosystem. It can analyze logs, suggest remediations, or even help draft declarative policies without compromising the host system's security.
*   **Integration Point:** Can query the `adr-ledger` to understand the historical state of a machine or interface with `voidnxsec`'s Go API to trigger safe, sandboxed diagnostic routines.

## The Macro-Architecture Flow

1.  **AI-Assisted Policy Design:** A user interacts with an LLM via `securellm-mcp` to design a secure OS deployment policy.
2.  **Declarative Record:** This policy is formalized and recorded in the `adr-ledger`.
3.  **Execution:** `voidnxsec` (via the `void-fortress-framework`) begins executing the deployment on the target hardware.
4.  **Verification Loop:** As `voidnxsec` completes each phase, it hashes the state and sends it to the `adr-ledger` for verification against the original policy.
5.  **Secure Diagnostics:** If a phase fails, `securellm-mcp` can securely query the JSONL error logs and the `adr-ledger` to provide context-aware debugging to the user.

---
*Note: This ecosystem map is a living document and will evolve as these foundational projects mature and merge.*
