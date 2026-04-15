# Contributing to Voidnxsec

First off, thank you for considering contributing to Voidnxsec! It's people like you that make Voidnxsec such a great tool for the Linux OS development community.

## 1. Where do I go from here?

If you've noticed a bug or have a feature request, make sure to check our issue tracker to see if someone else in the community has already created a ticket. If not, go ahead and make one!

## 2. Setting up your environment

Voidnxsec relies heavily on Nix for reproducible environments. To get started:

1. Install Nix.
2. Ensure flakes are enabled.
3. Run `nix develop` in the root of the project to enter the unified development environment.

## 3. Architecture & Guidelines

Voidnxsec is a multi-language monorepo (Rust, Go, C, C++). 
* **Rust**: Used for orchestration, safety-critical tasks, and complex logic. Follow standard `rustfmt` and `clippy` guidelines.
* **Go**: Used for API layers, network services, and concurrency. Follow standard `gofmt` guidelines.
* **C/C++**: Used for very low-level Linux interfacing, debugging hooks, and system calls. 

Please ensure you run the appropriate formatters and tests before submitting a Pull Request.

## 4. Submitting a Pull Request

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Make your changes (ensure you add tests if applicable!).
4. Push your branch and open a Pull Request against the `main` branch.
5. Provide a clear description of the problem you are solving and the solution you have implemented.

We will review your PR as soon as possible. Thank you for your contribution!
