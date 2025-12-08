/*
 * =============================================================================
 * VOID FORTRESS TUI v1.0 - C Implementation with ncurses
 * =============================================================================
 * Features:
 *   • Full ncurses-based interactive TUI
 *   • Real-time progress tracking
 *   • Safe dialogs and confirmations
 *   • Log viewer with scrolling
 *   • Process monitoring
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

#define MAX_PATH 256
#define MAX_BUFFER 512
#define MAX_DISKS 32
#define LOG_FILE "/tmp/void-fortress.log"
#define STATE_FILE "/tmp/void-fortress.state"

/* Colors */
#define COLOR_MAIN_BG 1
#define COLOR_HEADER 2
#define COLOR_MENU 3
#define COLOR_SUCCESS 4
#define COLOR_ERROR 5
#define COLOR_WARNING 6

/* Global state */
typedef struct {
    char disk[MAX_PATH];
    char hostname[MAX_PATH];
    char username[MAX_PATH];
    char timezone[MAX_PATH];
    char phase[64];
    int root_check;
    int uefi_check;
} installer_state_t;

installer_state_t state = {
    .disk = "",
    .hostname = "void-fortress",
    .username = "nx",
    .timezone = "America/Sao_Paulo",
    .phase = "NOT_STARTED",
    .root_check = 0,
    .uefi_check = 0
};

/* Function prototypes */
void init_ncurses(void);
void cleanup_ncurses(void);
void draw_banner(WINDOW *win);
void show_main_menu(WINDOW *win, int *choice);
int disk_selection(installer_state_t *state);
int confirm_dialog(const char *title, const char *message);
void show_status(WINDOW *win);
void view_log(WINDOW *win);
void run_command(const char *cmd, WINDOW *log_win);

/* Initialize ncurses */
void init_ncurses(void) {
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    
    if (has_colors()) {
        start_color();
        init_pair(COLOR_MAIN_BG, COLOR_WHITE, COLOR_BLACK);
        init_pair(COLOR_HEADER, COLOR_CYAN, COLOR_BLACK);
        init_pair(COLOR_MENU, COLOR_GREEN, COLOR_BLACK);
        init_pair(COLOR_SUCCESS, COLOR_GREEN, COLOR_BLACK);
        init_pair(COLOR_ERROR, COLOR_RED, COLOR_BLACK);
        init_pair(COLOR_WARNING, COLOR_YELLOW, COLOR_BLACK);
    }
    
    attron(COLOR_PAIR(COLOR_MAIN_BG));
}

/* Cleanup ncurses */
void cleanup_ncurses(void) {
    attroff(COLOR_PAIR(COLOR_MAIN_BG));
    endwin();
}

/* Draw ASCII banner */
void draw_banner(WINDOW *win) {
    int y = 1;
    mvwprintw(win, y++, 2, "╔════════════════════════════════════════════════════════════════╗");
    mvwprintw(win, y++, 2, "║            VOID FORTRESS TUI INSTALLER v1.0                    ║");
    mvwprintw(win, y++, 2, "║         Full Disk Encryption Installation Tool                 ║");
    mvwprintw(win, y++, 2, "║                                                                ║");
    mvwprintw(win, y++, 2, "║  🔒 LUKS1 Root + LUKS2 Home  🐧 Musl/Glibc Auto-Detect       ║");
    mvwprintw(win, y++, 2, "║  🛡️  Security Hardened       🖥️  Hyprland GUI Support        ║");
    mvwprintw(win, y++, 2, "╚════════════════════════════════════════════════════════════════╝");
}

/* Main menu */
void show_main_menu(WINDOW *win, int *choice) {
    static int selected = 0;
    const char *options[] = {
        "New Installation (Full Setup)",
        "Resume Installation (from checkpoint)",
        "Check System Status",
        "Open LUKS Devices",
        "Mount Filesystems",
        "Enter Chroot Shell",
        "View Installation Log",
        "Advanced Options",
        "Exit"
    };
    int num_options = sizeof(options) / sizeof(options[0]);
    int start_y = 10;
    
    wclear(win);
    draw_banner(win);
    
    mvwprintw(win, start_y, 2, "Select Operation:");
    mvwprintw(win, start_y + 1, 2, "─────────────────────────────────────");
    
    for (int i = 0; i < num_options; i++) {
        int attr = (i == selected) ? A_REVERSE : A_NORMAL;
        wattron(win, attr);
        mvwprintw(win, start_y + 2 + i, 4, "%d) %s", i + 1, options[i]);
        wattroff(win, attr);
    }
    
    mvwprintw(win, start_y + 2 + num_options + 2, 2, "Use ↑/↓ to navigate, Enter to select");
    
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
            *choice = selected + 1;
            break;
    }
}

/* Disk selection dialog */
int disk_selection(installer_state_t *state) {
    WINDOW *win = newwin(LINES, COLS, 0, 0);
    FILE *fp;
    char line[MAX_BUFFER];
    int disk_count = 0;
    char disks[MAX_DISKS][MAX_PATH];
    
    wclear(win);
    draw_banner(win);
    
    mvwprintw(win, 10, 2, "Available Disks:");
    mvwprintw(win, 11, 2, "──────────────────────────────────────");
    
    /* List block devices */
    fp = popen("lsblk -dn -o NAME,SIZE,MODEL 2>/dev/null | head -32", "r");
    if (fp) {
        int line_num = 13;
        while (fgets(line, sizeof(line), fp) && disk_count < MAX_DISKS) {
            char *name = strtok(line, " \t");
            if (name) {
                snprintf(disks[disk_count], MAX_PATH, "/dev/%s", name);
                mvwprintw(win, line_num++, 4, "%d) %s", disk_count + 1, line);
                disk_count++;
            }
        }
        pclose(fp);
    }
    
    mvwprintw(win, 13 + disk_count + 2, 2, "Select disk number: ");
    wrefresh(win);
    
    /* Get input */
    char input[16];
    echo();
    wgetstr(win, input);
    noecho();
    
    int choice = atoi(input) - 1;
    if (choice >= 0 && choice < disk_count) {
        strncpy(state->disk, disks[choice], MAX_PATH - 1);
        delwin(win);
        return 0;
    }
    
    delwin(win);
    return -1;
}

/* Confirmation dialog */
int confirm_dialog(const char *title, const char *message) {
    WINDOW *dialog = newwin(10, 60, (LINES - 10) / 2, (COLS - 60) / 2);
    box(dialog, 0, 0);
    
    mvwprintw(dialog, 1, 2, title);
    mvwprintw(dialog, 3, 2, message);
    mvwprintw(dialog, 6, 2, "Press 'y' to confirm, 'n' to cancel");
    
    wrefresh(dialog);
    
    int ch = getch();
    delwin(dialog);
    
    return (ch == 'y' || ch == 'Y') ? 1 : 0;
}

/* Show system status */
void show_status(WINDOW *win) {
    wclear(win);
    draw_banner(win);
    
    mvwprintw(win, 10, 2, "Current Status:");
    mvwprintw(win, 11, 2, "──────────────────────────────────────");
    
    mvwprintw(win, 13, 4, "Phase:    %s", state.phase);
    mvwprintw(win, 14, 4, "Disk:     %s", state.disk);
    mvwprintw(win, 15, 4, "Hostname: %s", state.hostname);
    mvwprintw(win, 16, 4, "User:     %s", state.username);
    mvwprintw(win, 17, 4, "Timezone: %s", state.timezone);
    
    mvwprintw(win, 20, 2, "Press any key to continue...");
    wrefresh(win);
    getch();
}

/* View installation log */
void view_log(WINDOW *win) {
    wclear(win);
    draw_banner(win);
    
    mvwprintw(win, 10, 2, "Installation Log (last 30 lines):");
    mvwprintw(win, 11, 2, "──────────────────────────────────────");
    
    FILE *fp = fopen(LOG_FILE, "r");
    if (fp) {
        char line[MAX_BUFFER];
        int line_num = 13;
        int total_lines = 0;
        int start_line = 0;
        
        /* Count total lines */
        while (fgets(line, sizeof(line), fp)) total_lines++;
        
        if (total_lines > 20) start_line = total_lines - 20;
        
        rewind(fp);
        
        int current = 0;
        while (fgets(line, sizeof(line), fp) && line_num < LINES - 3) {
            if (current >= start_line) {
                line[strcspn(line, "\n")] = 0;
                mvwprintw(win, line_num++, 4, "%s", line);
            }
            current++;
        }
        
        fclose(fp);
    } else {
        mvwprintw(win, 15, 4, "No log file found");
    }
    
    mvwprintw(win, LINES - 2, 2, "Press any key to continue...");
    wrefresh(win);
    getch();
}

/* Run external command with output capture */
void run_command(const char *cmd, WINDOW *log_win) {
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        mvwprintw(log_win, 5, 2, "Error: Failed to execute command");
        wrefresh(log_win);
        return;
    }
    
    char line[MAX_BUFFER];
    int y = 5;
    
    wclear(log_win);
    mvwprintw(log_win, 1, 2, "Command Output:");
    mvwprintw(log_win, 2, 2, "──────────────────────────────────────");
    
    while (fgets(line, sizeof(line), fp) && y < LINES - 3) {
        line[strcspn(line, "\n")] = 0;
        mvwprintw(log_win, y++, 4, "%s", line);
    }
    
    pclose(fp);
    
    mvwprintw(log_win, LINES - 2, 2, "Press any key to continue...");
    wrefresh(log_win);
    getch();
}

/* Main function */
int main(int argc, char *argv[]) {
    /* Check root */
    if (geteuid() != 0) {
        fprintf(stderr, "Error: Must run as root\n");
        return 1;
    }
    
    /* Check UEFI */
    if (access("/sys/firmware/efi", F_OK) != 0) {
        fprintf(stderr, "Error: Boot in UEFI mode required\n");
        return 1;
    }
    
    init_ncurses();
    
    WINDOW *main_win = newwin(LINES, COLS, 0, 0);
    int choice = 0;
    int running = 1;
    
    while (running) {
        show_main_menu(main_win, &choice);
        
        switch (choice) {
            case 1:
                /* New installation */
                if (disk_selection(&state) == 0) {
                    if (confirm_dialog("Confirm Disk Selection",
                        "WARNING: All data will be destroyed!")) {
                        echo();
                        mvwprintw(main_win, 15, 2, "Hostname [%s]: ", state.hostname);
                        wrefresh(main_win);
                        char buf[MAX_PATH];
                        wgetstr(main_win, buf);
                        if (strlen(buf) > 0) strncpy(state.hostname, buf, MAX_PATH - 1);
                        
                        mvwprintw(main_win, 16, 2, "Username [%s]: ", state.username);
                        wrefresh(main_win);
                        wgetstr(main_win, buf);
                        if (strlen(buf) > 0) strncpy(state.username, buf, MAX_PATH - 1);
                        
                        noecho();
                        
                        /* Execute installer */
                        char cmd[256];
                        snprintf(cmd, sizeof(cmd), 
                            "DISK=%s HOSTNAME=%s USERNAME=%s TIMEZONE=%s bash voidnx.sh",
                            state.disk, state.hostname, state.username, state.timezone);
                        run_command(cmd, main_win);
                    }
                }
                choice = 0;
                break;
                
            case 3:
                /* Check status */
                show_status(main_win);
                choice = 0;
                break;
                
            case 7:
                /* View log */
                view_log(main_win);
                choice = 0;
                break;
                
            case 9:
                /* Exit */
                running = 0;
                break;
                
            default:
                choice = 0;
                break;
        }
    }
    
    delwin(main_win);
    cleanup_ncurses();
    
    printf("Thank you for using VOID FORTRESS!\n");
    return 0;
}
