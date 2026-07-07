{ ... }:
# System hardening: CIS Benchmark Level 2 + ANSSI-BP-028 Enhanced
# References: CIS Linux, ANSSI-BP-028 v2.0, NSA/CISA, Lynis recommendations
{
  # --- AppArmor (ANSSI Intermediary+, available in NixOS 2026) ---
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true;
  };

  # --- Audit subsystem (ANSSI mandatory from Intermediary level) ---
  security.audit.enable = true;
  security.auditd.enable = true;

  # --- sysctl: kernel hardening ---
  boot.kernel.sysctl = {
    # Kernel pointer hiding
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;

    # BPF restrictions (CIS Level 2)
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;

    # ptrace restriction — only parent can ptrace child
    "kernel.yama.ptrace_scope" = 2;

    # perf events restriction
    "kernel.perf_event_paranoid" = 3;

    # SysRq disabled
    "kernel.sysrq" = 0;

    # Core dumps disabled (prevent credential leaks)
    "fs.suid_dumpable" = 0;
    "kernel.core_uses_pid" = 1;

    # Filesystem hardening
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;

    # --- sysctl: network hardening (ANSSI-BP-028) ---
    # IPv4
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.tcp_timestamps" = 0;
    # IPv6
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
  };

  # --- sudo hardening ---
  # No cached credentials (timestamp_timeout=0 — same as voidnx.sh)
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    extraConfig = ''
      Defaults timestamp_timeout=0
      Defaults use_pty
      Defaults logfile=/var/log/sudo.log
    '';
  };

  # --- PAM: login rate limiting ---
  security.pam.loginLimits = [
    { domain = "*"; type = "hard"; item = "core"; value = "0"; }
    { domain = "*"; type = "hard"; item = "nproc"; value = "65535"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65535"; }
  ];

  # --- fail2ban (Lynis recommendation) ---
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
      factor = "2";
      maxtime = "168h";
    };
    jails = {
      sshd.settings = {
        enabled = true;
        port = "ssh";
        filter = "sshd";
        maxretry = 3;
        bantime = "1h";
      };
    };
  };

  # --- Polkit: restrict privilege escalation ---
  security.polkit.enable = true;
}
