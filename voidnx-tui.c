/* POSIX.1-2008 required for popen/pclose */
#define _POSIX_C_SOURCE 200809L

/*
 * =============================================================================
 * VOID FORTRESS TUI v2.0 - C Implementation with ncurses
 * =============================================================================
 * Features:
 *   - Full ncurses-based interactive TUI
 *   - Void Linux FDE installation (voidnx.sh backend)
 *   - NixOS declarative bootstrap (disko + Lanzaboote + TPM2 + sops-nix)
 *   - Real-time progress tracking with JSONL log viewer
 *   - Safe confirmation dialogs
 *   - Process monitoring
 * =============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ncurses.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>

#define MAX_PATH    256
#define MAX_BUFFER  512
#define MAX_DISKS   32
#define LOG_FILE    "/tmp/void-fortress.log"
#define STATE_FILE  "/tmp/void-fortress.state"

/* Colors */
#define COLOR_MAIN_BG   1
#define COLOR_HEADER    2
#define COLOR_MENU      3
#define COLOR_SUCCESS   4
#define COLOR_ERROR     5
#define COLOR_WARNING   6
#define COLOR_NIXOS     7

/* Global state */
typedef struct {
    char disk[MAX_PATH];
    char hostname[MAX_PATH];
    char username[MAX_PATH];
    char timezone[MAX_PATH];
    char phase[64];
    /* NixOS bootstrap state */
    char nixos_profile[16];   /* "server" | "laptop" */
    char nixos_target[MAX_PATH];
    int  nixos_local;         /* 1 = local install, 0 = remote via SSH */
    int  root_check;
    int  uefi_check;
} installer_state_t;

installer_state_t state = {
    .disk         = "",
    .hostname     = "voidnx",
    .username     = "nx",
    .timezone     = "America/Sao_Paulo",
    .phase        = "NOT_STARTED",
    .nixos_profile = "laptop",
    .nixos_target  = "localhost",
    .nixos_local   = 1,
    .root_check   = 0,
    .uefi_check   = 0,
};

/* Forward declarations */
void init_ncurses(void);
void cleanup_ncurses(void);
void draw_banner(WINDOW *win, const char *subtitle);
void show_main_menu(WINDOW *win, int *choice);
int  disk_selection(installer_state_t *s);
int  confirm_dialog(const char *title, const char *message);
void show_status(WINDOW *win);
void view_log(WINDOW *win);
void run_command(const char *cmd, WINDOW *log_win);
/* NixOS */
void nixos_bootstrap_menu(WINDOW *win);
int  nixos_profile_select(WINDOW *win, installer_state_t *s);
void nixos_run_bootstrap(WINDOW *win, installer_state_t *s);
void nixos_enroll_tpm(WINDOW *win);
void nixos_run_audit(WINDOW *win);

/* ── ncurses helpers ──────────────────────────────────────────────────── */

void init_ncurses(void) {
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);

    if (has_colors()) {
        start_color();
        use_default_colors();
        init_pair(COLOR_MAIN_BG, COLOR_WHITE,   COLOR_BLACK);
        init_pair(COLOR_HEADER,  COLOR_CYAN,    COLOR_BLACK);
        init_pair(COLOR_MENU,    COLOR_GREEN,   COLOR_BLACK);
        init_pair(COLOR_SUCCESS, COLOR_GREEN,   COLOR_BLACK);
        init_pair(COLOR_ERROR,   COLOR_RED,     COLOR_BLACK);
        init_pair(COLOR_WARNING, COLOR_YELLOW,  COLOR_BLACK);
        init_pair(COLOR_NIXOS,   COLOR_MAGENTA, COLOR_BLACK);
    }

    attron(COLOR_PAIR(COLOR_MAIN_BG));
}

void cleanup_ncurses(void) {
    attroff(COLOR_PAIR(COLOR_MAIN_BG));
    endwin();
}

void draw_banner(WINDOW *win, const char *subtitle) {
    wattron(win, COLOR_PAIR(COLOR_HEADER) | A_BOLD);
    mvwprintw(win, 1, 2, "+-----------------------------------------------------------------+");
    mvwprintw(win, 2, 2, "|          VOID FORTRESS TUI v2.0 — VoidNxSEC                    |");
    mvwprintw(win, 3, 2, "|  LUKS2/Argon2id  |  NixOS Bootstrap  |  Lanzaboote + TPM2      |");
    if (subtitle && strlen(subtitle) > 0) {
        mvwprintw(win, 4, 2, "|  %-63s|", subtitle);
    } else {
        mvwprintw(win, 4, 2, "|                                                                 |");
    }
    mvwprintw(win, 5, 2, "+-----------------------------------------------------------------+");
    wattroff(win, COLOR_PAIR(COLOR_HEADER) | A_BOLD);
}

/* ── Main menu ────────────────────────────────────────────────────────── */

void show_main_menu(WINDOW *win, int *choice) {
    static int selected = 0;
    const char *options[] = {
        "1) Void Linux — New Installation  (FDE, LUKS2, Argon2id)",
        "2) Void Linux — Resume Installation",
        "3) Check System Status",
        "4) Open LUKS Devices",
        "5) Mount Filesystems",
        "6) Enter Chroot Shell",
        "7) View Installation Log",
        "8) [NixOS] Bootstrap (server / laptop)",
        "9) [NixOS] Enroll TPM2 (post-boot)",
        "0) Exit",
    };
    int num_options = 10;
    int start_y = 8;

    wclear(win);
    draw_banner(win, "");

    wattron(win, COLOR_PAIR(COLOR_MENU) | A_BOLD);
    mvwprintw(win, start_y, 2, "Select Operation:");
    mvwprintw(win, start_y + 1, 2, "-------------------------------------------------------------------");
    wattroff(win, COLOR_PAIR(COLOR_MENU) | A_BOLD);

    for (int i = 0; i < num_options; i++) {
        int is_nixos = (i == 7 || i == 8);
        int attr = (i == selected) ? A_REVERSE : A_NORMAL;

        if (is_nixos) wattron(win, COLOR_PAIR(COLOR_NIXOS));
        wattron(win, attr);
        mvwprintw(win, start_y + 2 + i, 4, "%-65s", options[i]);
        wattroff(win, attr);
        if (is_nixos) wattroff(win, COLOR_PAIR(COLOR_NIXOS));
    }

    mvwprintw(win, start_y + num_options + 4, 2,
              "Arrow keys / Enter to select    q = quit");
    wrefresh(win);

    int ch = getch();
    switch (ch) {
        case KEY_UP:
            selected = (selected - 1 + num_options) % num_options;
            break;
        case KEY_DOWN:
            selected = (selected + 1) % num_options;
            break;
        case '\n':
        case '\r':
            *choice = (selected == 9) ? 0 : selected + 1;
            break;
        case 'q':
        case 'Q':
            *choice = 0;
            break;
        default:
            break;
    }
}

/* ── Disk selection ───────────────────────────────────────────────────── */

int disk_selection(installer_state_t *s) {
    WINDOW *win = newwin(LINES, COLS, 0, 0);
    FILE *fp;
    char line[MAX_BUFFER];
    int disk_count = 0;
    char disks[MAX_DISKS][MAX_PATH];

    wclear(win);
    draw_banner(win, "Disk Selection");

    mvwprintw(win, 8, 2, "Available Disks:");
    mvwprintw(win, 9, 2, "------------------------------------");

    fp = popen("lsblk -dn -o NAME,SIZE,MODEL 2>/dev/null | head -32", "r");
    if (fp) {
        int line_num = 11;
        while (fgets(line, sizeof(line), fp) && disk_count < MAX_DISKS) {
            char *name = strtok(line, " \t");
            if (name) {
                snprintf(disks[disk_count], MAX_PATH, "/dev/%s", name);
                /* re-read full line for display */
                mvwprintw(win, line_num++, 4, "%d) /dev/%s", disk_count + 1, name);
                disk_count++;
            }
        }
        pclose(fp);
    }

    mvwprintw(win, 11 + disk_count + 2, 2, "Select disk number [1-%d]: ", disk_count);
    wrefresh(win);

    char input[16] = {0};
    echo();
    wgetnstr(win, input, (int)sizeof(input) - 1);
    noecho();

    int sel = atoi(input) - 1;
    if (sel >= 0 && sel < disk_count) {
        strncpy(s->disk, disks[sel], MAX_PATH - 1);
        delwin(win);
        return 0;
    }

    delwin(win);
    return -1;
}

/* ── Confirm dialog ───────────────────────────────────────────────────── */

int confirm_dialog(const char *title, const char *message) {
    int dh = 10, dw = 64;
    WINDOW *dialog = newwin(dh, dw, (LINES - dh) / 2, (COLS - dw) / 2);
    box(dialog, 0, 0);

    wattron(dialog, COLOR_PAIR(COLOR_WARNING) | A_BOLD);
    mvwprintw(dialog, 1, 2, "  %s", title);
    wattroff(dialog, COLOR_PAIR(COLOR_WARNING) | A_BOLD);

    mvwprintw(dialog, 3, 2, "%s", message);
    mvwprintw(dialog, 5, 2, "----------------------------------------");
    mvwprintw(dialog, 7, 2, "Press 'y' to confirm, any other key = cancel");

    wrefresh(dialog);

    int ch = getch();
    delwin(dialog);
    return (ch == 'y' || ch == 'Y') ? 1 : 0;
}

/* ── Status screen ────────────────────────────────────────────────────── */

void show_status(WINDOW *win) {
    wclear(win);
    draw_banner(win, "System Status");

    /* Read state file */
    char phase[64] = "unknown";
    FILE *sf = fopen(STATE_FILE, "r");
    if (sf) {
        char line[256];
        while (fgets(line, sizeof(line), sf)) {
            if (strncmp(line, "STATE=", 6) == 0) {
                sscanf(line + 6, "%63s", phase);
            }
        }
        fclose(sf);
    }

    mvwprintw(win, 8,  2, "Void Linux Installer:");
    mvwprintw(win, 9,  2, "---------------------------------------------");
    mvwprintw(win, 10, 4, "Phase:    %s", phase);
    mvwprintw(win, 11, 4, "Disk:     %s", strlen(state.disk) ? state.disk : "(not set)");
    mvwprintw(win, 12, 4, "Hostname: %s", state.hostname);
    mvwprintw(win, 13, 4, "User:     %s", state.username);
    mvwprintw(win, 14, 4, "Timezone: %s", state.timezone);

    wattron(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
    mvwprintw(win, 16, 2, "NixOS Bootstrap:");
    wattroff(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
    mvwprintw(win, 17, 2, "---------------------------------------------");
    mvwprintw(win, 18, 4, "Profile:  %s", state.nixos_profile);
    mvwprintw(win, 19, 4, "Target:   %s", state.nixos_target);
    mvwprintw(win, 20, 4, "Mode:     %s", state.nixos_local ? "local" : "remote SSH");

    /* Quick LUKS check */
    FILE *fp = popen("ls /dev/mapper/ 2>/dev/null | grep -v control | tr '\\n' ' '", "r");
    if (fp) {
        char mappers[256] = {0};
        if (fgets(mappers, sizeof(mappers), fp))
            mvwprintw(win, 22, 4, "LUKS open: %s", strlen(mappers) > 1 ? mappers : "none");
        pclose(fp);
    }

    mvwprintw(win, LINES - 2, 2, "Press any key to return...");
    wrefresh(win);
    getch();
}

/* ── Log viewer ───────────────────────────────────────────────────────── */

void view_log(WINDOW *win) {
    wclear(win);
    draw_banner(win, "Installation Log");

    mvwprintw(win, 8,  2, "Log: %s  (last lines)", LOG_FILE);
    mvwprintw(win, 9,  2, "---------------------------------------------");

    FILE *fp = fopen(LOG_FILE, "r");
    if (fp) {
        char lines[40][MAX_BUFFER];
        int count = 0;
        while (fgets(lines[count % 40], sizeof(lines[0]), fp))
            count++;
        fclose(fp);

        int show = count < 20 ? count : 20;
        int start = count < 40 ? 0 : (count % 40);
        for (int i = 0; i < show; i++) {
            int idx = (start + (count - show) + i) % 40;
            lines[idx][strcspn(lines[idx], "\n")] = 0;
            mvwprintw(win, 11 + i, 4, "%-70.70s", lines[idx]);
        }
    } else {
        mvwprintw(win, 12, 4, "No log file found at %s", LOG_FILE);
    }

    mvwprintw(win, LINES - 2, 2, "Press any key to return...");
    wrefresh(win);
    getch();
}

/* ── Command runner ───────────────────────────────────────────────────── */

void run_command(const char *cmd, WINDOW *log_win) {
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        mvwprintw(log_win, 5, 2, "[ERROR] Failed to execute: %s", cmd);
        wrefresh(log_win);
        getch();
        return;
    }

    char line[MAX_BUFFER];
    int y = 5;

    wclear(log_win);
    draw_banner(log_win, "Running...");
    mvwprintw(log_win, 7, 2, "$ %s", cmd);
    mvwprintw(log_win, 8, 2, "---------------------------------------------");

    while (fgets(line, sizeof(line), fp)) {
        if (y >= LINES - 3) {
            /* Scroll: shift lines up */
            wscrl(log_win, 1);
            y = LINES - 4;
        }
        line[strcspn(line, "\n")] = 0;
        mvwprintw(log_win, y++, 4, "%-74.74s", line);
        wrefresh(log_win);
    }

    pclose(fp);
    mvwprintw(log_win, LINES - 2, 2, "Done. Press any key to return...");
    wrefresh(log_win);
    getch();
}

/* ── NixOS Bootstrap ──────────────────────────────────────────────────── */

int nixos_profile_select(WINDOW *win, installer_state_t *s) {
    wclear(win);
    draw_banner(win, "NixOS Bootstrap — Profile Selection");

    wattron(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
    mvwprintw(win, 8,  2, "Select machine profile:");
    wattroff(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
    mvwprintw(win, 9,  2, "---------------------------------------------");

    mvwprintw(win, 11, 4, "1) server  — headless, minimal, SSH hardened");
    mvwprintw(win, 12, 4, "             nftables, fail2ban, AIDE, auditd");
    mvwprintw(win, 14, 4, "2) laptop  — NVMe 3-partition, WiFi iwd,");
    mvwprintw(win, 15, 4, "             TPM2 hibernate, Lanzaboote SB");
    mvwprintw(win, 17, 4, "q) Back to main menu");

    mvwprintw(win, 19, 2, "Both profiles:");
    mvwprintw(win, 20, 4, "LUKS2/Argon2id  Impermanence  sops-nix  AppArmor");

    mvwprintw(win, 22, 2, "Select [1/2/q]: ");
    wrefresh(win);

    echo();
    char input[4] = {0};
    wgetnstr(win, input, 2);
    noecho();

    if (input[0] == '1') {
        strncpy(s->nixos_profile, "server", sizeof(s->nixos_profile) - 1);
    } else if (input[0] == '2') {
        strncpy(s->nixos_profile, "laptop", sizeof(s->nixos_profile) - 1);
    } else {
        return -1;
    }

    /* Target host */
    wclear(win);
    draw_banner(win, "NixOS Bootstrap — Target");

    mvwprintw(win, 8,  2, "Profile: %s", s->nixos_profile);
    mvwprintw(win, 10, 2, "Install mode:");
    mvwprintw(win, 11, 4, "1) Local  — install directly on this machine");
    mvwprintw(win, 12, 4, "2) Remote — deploy via SSH to another host");
    mvwprintw(win, 14, 2, "Select [1/2]: ");
    wrefresh(win);

    wgetnstr(win, input, 2);
    if (input[0] == '2') {
        s->nixos_local = 0;
        mvwprintw(win, 16, 2, "Target IP or hostname: ");
        wrefresh(win);
        echo();
        wgetnstr(win, s->nixos_target, MAX_PATH - 1);
        noecho();
    } else {
        s->nixos_local = 1;
        strncpy(s->nixos_target, "localhost", MAX_PATH - 1);
    }

    return 0;
}

void nixos_run_bootstrap(WINDOW *win, installer_state_t *s) {
    /* Build LUKS passphrase securely */
    wclear(win);
    draw_banner(win, "NixOS Bootstrap — LUKS Passphrase");

    mvwprintw(win, 8,  2, "Profile:  %s", s->nixos_profile);
    mvwprintw(win, 9,  2, "Target:   %s", s->nixos_local ? "localhost" : s->nixos_target);
    mvwprintw(win, 10, 2, "Disk:     %s",
        strcmp(s->nixos_profile, "laptop") == 0 ? "/dev/nvme0n1" : "/dev/sda");
    mvwprintw(win, 12, 2, "LUKS Passphrase (hidden): ");
    wrefresh(win);

    /* Read passphrase without echo */
    char pass1[256] = {0}, pass2[256] = {0};
    noecho();
    wgetnstr(win, pass1, (int)sizeof(pass1) - 1);

    mvwprintw(win, 13, 2, "Confirm passphrase:        ");
    wrefresh(win);
    wgetnstr(win, pass2, (int)sizeof(pass2) - 1);
    echo();

    if (strcmp(pass1, pass2) != 0) {
        mvwprintw(win, 15, 2, "[ERROR] Passphrases do not match.");
        wrefresh(win);
        memset(pass1, 0, sizeof(pass1));
        memset(pass2, 0, sizeof(pass2));
        getch();
        return;
    }

    /* Write passphrase to tmpfs (cleared on boot) */
    FILE *pf = fopen("/tmp/luks-pass", "w");
    if (!pf) {
        mvwprintw(win, 15, 2, "[ERROR] Cannot write /tmp/luks-pass");
        wrefresh(win);
        memset(pass1, 0, sizeof(pass1));
        getch();
        return;
    }
    fprintf(pf, "%s", pass1);
    fclose(pf);
    chmod("/tmp/luks-pass", 0600);
    memset(pass1, 0, sizeof(pass1));
    memset(pass2, 0, sizeof(pass2));

    if (!confirm_dialog("Confirm NixOS Bootstrap",
            "This will WIPE the target disk. Continue?")) {
        unlink("/tmp/luks-pass");
        return;
    }

    /* Build command */
    char cmd[512];
    if (s->nixos_local) {
        snprintf(cmd, sizeof(cmd),
            "bash scripts/bootstrap-nixos.sh %s localhost --luks-pass /tmp/luks-pass",
            s->nixos_profile);
    } else {
        snprintf(cmd, sizeof(cmd),
            "bash scripts/bootstrap-nixos.sh %s %s --luks-pass /tmp/luks-pass",
            s->nixos_profile, s->nixos_target);
    }

    run_command(cmd, win);
    unlink("/tmp/luks-pass");
}

void nixos_enroll_tpm(WINDOW *win) {
    if (!confirm_dialog("Enroll TPM2",
            "Bind LUKS to TPM2 PCR 7+9. Run after first boot.")) {
        return;
    }
    run_command("bash scripts/enroll-tpm.sh", win);
}

void nixos_run_audit(WINDOW *win) {
    run_command("bash scripts/audit.sh", win);
}

void nixos_bootstrap_menu(WINDOW *win) {
    int sel = 0;
    const char *opts[] = {
        "1) Deploy NixOS (disko + Lanzaboote + sops-nix)",
        "2) Enroll TPM2 for LUKS auto-unlock (post-boot)",
        "3) Run Lynis security audit",
        "4) Back",
    };
    int n = 4;

    while (1) {
        wclear(win);
        draw_banner(win, "NixOS Bootstrap Menu");

        wattron(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
        mvwprintw(win, 8, 2, "NixOS Operations:");
        wattroff(win, COLOR_PAIR(COLOR_NIXOS) | A_BOLD);
        mvwprintw(win, 9, 2, "---------------------------------------------");

        for (int i = 0; i < n; i++) {
            int attr = (i == sel) ? A_REVERSE : A_NORMAL;
            if (i < 3) wattron(win, COLOR_PAIR(COLOR_NIXOS));
            wattron(win, attr);
            mvwprintw(win, 11 + i, 4, "%-60s", opts[i]);
            wattroff(win, attr);
            if (i < 3) wattroff(win, COLOR_PAIR(COLOR_NIXOS));
        }

        mvwprintw(win, 11 + n + 2, 2, "Arrow keys / Enter    q = Back");
        wrefresh(win);

        int ch = getch();
        switch (ch) {
            case KEY_UP:   sel = (sel - 1 + n) % n; break;
            case KEY_DOWN: sel = (sel + 1) % n;      break;
            case '\n': case '\r':
                if (sel == 0) {
                    if (nixos_profile_select(win, &state) == 0)
                        nixos_run_bootstrap(win, &state);
                } else if (sel == 1) {
                    nixos_enroll_tpm(win);
                } else if (sel == 2) {
                    nixos_run_audit(win);
                } else {
                    return;
                }
                break;
            case 'q': case 'Q': return;
        }
    }
}

/* ── Main ─────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    if (geteuid() != 0) {
        fprintf(stderr, "Error: Must run as root\n");
        return 1;
    }
    if (access("/sys/firmware/efi", F_OK) != 0) {
        fprintf(stderr, "Error: UEFI mode required\n");
        return 1;
    }

    init_ncurses();
    scrollok(stdscr, TRUE);

    WINDOW *main_win = newwin(LINES, COLS, 0, 0);
    scrollok(main_win, TRUE);

    int choice = 0;
    int running = 1;
    char cmd[1200];

    while (running) {
        show_main_menu(main_win, &choice);

        switch (choice) {
            case 1: /* Void Linux: New Installation */
                if (disk_selection(&state) == 0) {
                    if (confirm_dialog("WARNING — All data will be destroyed!",
                            "This will wipe the selected disk and install Void Linux.")) {
                        echo();
                        char buf[MAX_PATH];
                        mvwprintw(main_win, 15, 2, "Hostname [%s]: ", state.hostname);
                        wrefresh(main_win);
                        wgetnstr(main_win, buf, MAX_PATH - 1);
                        if (strlen(buf) > 0)
                            snprintf(state.hostname, MAX_PATH, "%s", buf);

                        mvwprintw(main_win, 16, 2, "Username [%s]: ", state.username);
                        wrefresh(main_win);
                        wgetnstr(main_win, buf, MAX_PATH - 1);
                        if (strlen(buf) > 0)
                            snprintf(state.username, MAX_PATH, "%s", buf);
                        noecho();

                        snprintf(cmd, sizeof(cmd),
                            "DISK='%s' HOSTNAME='%s' USERNAME='%s' TIMEZONE='%s' bash voidnx.sh",
                            state.disk, state.hostname, state.username, state.timezone);
                        run_command(cmd, main_win);
                    }
                }
                choice = 0;
                break;

            case 2: /* Void Linux: Resume */
                run_command("bash voidnx.sh resume", main_win);
                choice = 0;
                break;

            case 3: /* Status */
                show_status(main_win);
                choice = 0;
                break;

            case 4: /* Open LUKS */
                run_command("bash voidnx.sh open", main_win);
                choice = 0;
                break;

            case 5: /* Mount */
                run_command("bash voidnx.sh mount", main_win);
                choice = 0;
                break;

            case 6: /* Chroot shell — must exit ncurses */
                cleanup_ncurses();
                if (system("bash voidnx.sh shell") != 0) { /* shell exited */ }
                init_ncurses();
                main_win = newwin(LINES, COLS, 0, 0);
                scrollok(main_win, TRUE);
                choice = 0;
                break;

            case 7: /* Log viewer */
                view_log(main_win);
                choice = 0;
                break;

            case 8: /* NixOS Bootstrap menu */
                nixos_bootstrap_menu(main_win);
                choice = 0;
                break;

            case 9: /* NixOS Enroll TPM2 (shortcut) */
                nixos_enroll_tpm(main_win);
                choice = 0;
                break;

            case 0: /* Exit */
                running = 0;
                break;

            default:
                choice = 0;
                break;
        }
    }

    delwin(main_win);
    cleanup_ncurses();
    printf("VoidNxSEC — done.\n");
    return 0;
}
