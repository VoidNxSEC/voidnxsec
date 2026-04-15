# System Architecture: Voidnxsec

Voidnxsec is built to bridge the gap between low-level Linux OS phases and high-level declarative state management. This document outlines the core architecture and how the different language environments interact.

## 1. High-Level Concepts

*   **Non-Machine State Fields:** Voidnxsec targets states that are difficult to track or reproduce traditionally, such as transient boot phases, early kernel initialization parameters, and low-level device states.
*   **Deterministic Hashing:** We generate cryptographic hashes that represent the exact state of these low-level phases. If the hash matches, the state is verified as reproducible.
*   **Declarative Orchestration:** Instead of imperative scripts, Voidnxsec uses a declarative model (similar to Nix) to define what the state *should* be, and orchestrates the transition to that state.

## 2. Component Layout

Voidnxsec relies on a polyglot micro-architecture to leverage the best tools for each specific layer:

### Layer 1: The API & Tooling (Go)
*   **Path:** `/go-service`
*   **Role:** Acts as the entry point for users and CI/CD pipelines. It provides REST/gRPC endpoints, CLI tooling, and handles concurrent requests. It translates high-level user declarations into actionable orchestration tasks.

### Layer 2: The Orchestrator (Rust)
*   **Path:** `/rust-service`
*   **Role:** The brain of the operation. It receives tasks from the Go layer and determines the safe path to transition the OS state. Rust's memory safety and concurrency guarantees are critical here to prevent state corruption during orchestration.

### Layer 3: Low-Level Hooks & Intercepts (C / C++)
*   **Path:** `/c-app` and `/cpp-app`
*   **Role:** These components interface directly with the Linux kernel (via eBPF, netlink, or direct system calls). They are responsible for reading the "non-machine state fields", generating the deterministic hashes, and applying low-level state changes requested by the Rust Orchestrator.

## 3. Communication Flow

1.  **User/System** defines a desired OS state and sends it to the **Go API**.
2.  **Go API** validates the request and passes the desired state graph to the **Rust Orchestrator**.
3.  **Rust Orchestrator** communicates with the **C/C++ hooks** to query the current state hashes.
4.  The **C/C++ layer** inspects the kernel/hardware state, generates the hash, and returns it.
5.  If the current state hash differs from the desired state, the **Rust Orchestrator** commands the **C/C++ layer** to execute specific debugging and transition routines to align the states.

## 4. Future Roadmap & "Hacks"

As a project that aims to push the boundaries of modern OS management, we are exploring several "hacks" (unconventional but powerful techniques):
*   Dynamic eBPF loading for zero-downtime state introspection.
*   Kexec-based fast state resets without a full hardware reboot.
*   Deep integration with Nix flakes to provide immutable references to the tools generating the hashes.
