# Voidnxsec (Void Fortress)

**Voidnxsec** (formerly Void Fortress) is a next-generation orchestration and debugging framework designed to solve non-machine state field challenges. It facilitates low-level Linux development by providing deep debugging capabilities and deterministic hashing for low-level OS phases.

The ultimate goal of this project is to create more predictable workflows and enforce a declarative approach to Operating System management. It reimagines how we build, deploy, and manage OS environments in the modern era, incorporating a few novel hacks and designed from the ground up for open-source adoption.

## 🚀 Core Features

*   **Low-Level Debugging:** Advanced tools for inspecting and manipulating low-level Linux states.
*   **Deterministic State Hashing:** Generates reliable hashes for boot phases and very low-level OS states.
*   **Declarative Workflows:** Enables predictable and reproducible OS building and management.
*   **Multi-Language Architecture:** Built leveraging the strengths of Rust, Go, C, and C++.
*   **Nix Flake Integration:** Fully reproducible development environments using Nix and `flake-parts`.
*   **Legacy Full Disk Encryption (FDE):** Retains the battle-tested LUKS1/LUKS2 Void Linux automated installation capabilities.

---

## 🏗️ Architecture & Ecosystem

The project is structured as a modular monorepo:

*   **`rust-service/`**: Core orchestration and safety-critical components.
*   **`go-service/`**: API, tooling, and concurrent state management.
*   **`c-app/` & `cpp-app/`**: Low-level Linux interactions, kernel interfacing, and high-performance system hooks.
*   **`nix/`**: Modular development environments.
*   **`lib/` & `tools/`**: The Void Fortress execution framework.

See [`docs/BIG_PICTURE.md`](docs/BIG_PICTURE.md) and [`docs/ECOSYSTEM.md`](docs/ECOSYSTEM.md) for more details.

---

## 🛡️ The Void Fortress Legacy Framework

The foundational installer from the `void-fortress` project is retained here as the core execution layer for Void Linux environments. 

### Features of the Legacy Installer
- 🔒 **Full Disk Encryption:** LUKS1 for root partition (AES-XTS-Plain64, SHA512), LUKS2 for home partition (Argon2id).
- 🐧 **Void Linux Compatible:** Musl/glibc auto-detection, Void-native tools (`sfdisk`, `xbps-install`, `dracut`).
- 🛡️ **Security Hardened:** AppArmor integration, kernel security parameters, memory protection.
- 💾 **Smart Disk Detection:** Auto-detects NVMe, VDA (VM), SDA (HDD) with automatic partition sizing.

### Installer Branches & Usage
The original project maintains specific interfaces:
- **CLI Installer (Main)**: Run `sudo bash voidnx.sh`
- **TUI Interactive (Dev)**: Run `sudo bash voidnx-tui.sh` or compile the C TUI.
- **GUI + Hyprland**: Available in specific workflows.

## 🛠️ Getting Started (Modern Stack)

### Prerequisites
You need [Nix](https://nixos.org/download.html) installed with flakes enabled.

### Development Environment
Drop into the unified development shell which provides all necessary compilers (Rust, Go, C/C++) and tools:
```bash
nix develop
```

Or, drop into a specific language environment:
```bash
nix develop .#rust
nix develop .#go
nix develop .#c
nix develop .#cpp
```

## 🤝 Contributing
We welcome contributions! This project is aimed at broad open-source adoption. Please see [`CONTRIBUTING.md`](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## 📄 License
This project is licensed under the MIT License - see the [`LICENSE`](LICENSE) file for details.
