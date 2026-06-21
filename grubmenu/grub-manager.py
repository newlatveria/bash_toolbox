#!/usr/bin/env python3
"""
grub-manager.py — GRUB configuration GUI for Ubuntu 24.04
Runs as normal user. Elevates only at save time via pkexec helper.
Requires: python3-tk  (sudo apt install python3-tk)
"""

import os, sys, re, subprocess, tempfile
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox

GRUB_CFG  = Path("/etc/default/grub")
APPLY_BIN = "/usr/local/bin/grub-manager-apply"

BG      = "#1e1e2e"
SURFACE = "#181825"
BORDER  = "#313244"
TEXT    = "#cdd6f4"
SUBTEXT = "#6c7086"
ACCENT  = "#cba6f7"
GREEN   = "#a6e3a1"
RED     = "#f38ba8"
HOVER   = "#b4befe"

# ── helpers ───────────────────────────────────────────────────────────────────

def read_grub_cfg():
    cfg = {}
    if GRUB_CFG.exists():
        for line in GRUB_CFG.read_text().splitlines():
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip().strip('"')
    return cfg

def write_grub_cfg_to_tmp(cfg):
    original = GRUB_CFG.read_text() if GRUB_CFG.exists() else ""
    written, lines = set(), []
    for line in original.splitlines():
        s = line.strip()
        if s.startswith("#") or "=" not in s:
            lines.append(line); continue
        k = s.partition("=")[0].strip()
        if k in cfg:
            lines.append(f'{k}="{cfg[k]}"'); written.add(k)
        else:
            lines.append(line)
    for k, v in cfg.items():
        if k not in written:
            lines.append(f'{k}="{v}"')
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".grub", delete=False,
                                      dir="/tmp", prefix="grub-manager-")
    tmp.write("\n".join(lines) + "\n"); tmp.close()
    os.chmod(tmp.name, 0o644)
    return tmp.name

def get_boot_entries():
    p = Path("/boot/grub/grub.cfg")
    if not p.exists():
        return []
    try:
        text = p.read_text(errors="replace")
    except PermissionError:
        return []
    return re.findall(r'^(?:menuentry|submenu)\s+["\']([^"\']+)["\']',
                      text, re.MULTILINE)

def apply_via_pkexec(tmp_path):
    if not Path(APPLY_BIN).exists():
        return False, f"Helper not installed at {APPLY_BIN} — run: sudo bash install.sh"
    try:
        r = subprocess.run(["pkexec", APPLY_BIN, tmp_path],
                           capture_output=True, text=True, timeout=60)
        out = (r.stdout + r.stderr).strip()
        return r.returncode == 0, out or ("Done." if r.returncode == 0 else "Unknown error")
    except subprocess.TimeoutExpired:
        return False, "Timed out"
    except FileNotFoundError:
        return False, "pkexec not found"
    except Exception as e:
        return False, str(e)

# ── app ───────────────────────────────────────────────────────────────────────

class GrubManager(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Boot Options Manager")
        self.configure(bg=BG)
        self.resizable(True, True)
        self.minsize(640, 400)

        self.cfg     = read_grub_cfg()
        self.entries = get_boot_entries()

        # all tk vars up front
        self._var_default     = tk.StringVar()
        self._var_default_idx = tk.IntVar(value=0)
        self._var_timeout     = tk.IntVar(value=5)
        self._var_hidden      = tk.BooleanVar()
        self._var_quiet       = tk.BooleanVar()
        self._var_splash      = tk.BooleanVar()
        self._var_saved       = tk.BooleanVar()
        self._var_recovery    = tk.BooleanVar()
        self._status_var      = tk.StringVar(value="No unsaved changes")

        self._build()
        self._load()

    def _build(self):
        s = ttk.Style(self)
        s.theme_use("clam")
        s.configure("TSeparator", background=BORDER)
        s.configure("TCombobox",
                    fieldbackground=BORDER, background=BORDER,
                    foreground=TEXT, selectbackground=BORDER,
                    selectforeground=TEXT, arrowcolor=TEXT)
        s.map("TCombobox", fieldbackground=[("readonly", BORDER)],
              foreground=[("readonly", TEXT)])

        # ── header ──────────────────────────────────────────────────────────
        hdr = tk.Frame(self, bg=SURFACE)
        hdr.pack(fill="x")
        tk.Label(hdr, text="Boot Options Manager",
                 bg=SURFACE, fg=TEXT,
                 font=("Sans", 16, "bold")).pack(anchor="w", padx=20, pady=(14, 2))
        tk.Label(hdr, text="Change what happens when your computer starts",
                 bg=SURFACE, fg=SUBTEXT,
                 font=("Sans", 10)).pack(anchor="w", padx=20, pady=(0, 12))
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── content area (no canvas — direct pack) ───────────────────────────
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=16, pady=12)

        # Card: Default OS
        self._card(body, "DEFAULT BOOT SELECTION", [
            self._row_default,
        ])

        # Card: Timing
        self._card(body, "MENU TIMING", [
            lambda f: self._row_spin(f,
                "Seconds to show boot menu",
                "0 = boot immediately  |  −1 = wait forever",
                self._var_timeout, lo=-1, hi=120),
            lambda f: self._row_check(f,
                "Hide boot menu (boot silently)",
                "Menu still appears if you hold Shift at startup",
                self._var_hidden),
        ])

        # Card: Behaviour
        self._card(body, "BOOT BEHAVIOUR", [
            lambda f: self._row_check(f,
                "Show boot messages (verbose)",
                "Off = clean splash  |  On = technical boot text",
                self._var_quiet),
            lambda f: self._row_check(f,
                "Show graphical splash screen",
                "Ubuntu logo animation during boot",
                self._var_splash),
            lambda f: self._row_check(f,
                "Remember last OS chosen",
                "Auto-selects whichever you booted last time",
                self._var_saved),
        ])

        # Card: Recovery
        self._card(body, "RECOVERY", [
            lambda f: self._row_check(f,
                "Show recovery options in menu",
                "Allows booting into recovery mode if something goes wrong",
                self._var_recovery),
        ])

        # ── footer ───────────────────────────────────────────────────────────
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")
        foot = tk.Frame(self, bg=BG)
        foot.pack(fill="x", pady=10)

        self._status_lbl = tk.Label(foot, textvariable=self._status_var,
                                    bg=BG, fg=SUBTEXT, font=("Sans", 10))
        self._status_lbl.pack(side="left", padx=16)

        tk.Button(foot, text="Save & Apply",
                  command=self._on_apply,
                  bg=ACCENT, fg=BG, font=("Sans", 11, "bold"),
                  relief="flat", padx=20, pady=6, cursor="hand2",
                  activebackground=HOVER, activeforeground=BG,
                  ).pack(side="right", padx=16)

    # ── card builder ─────────────────────────────────────────────────────────

    def _card(self, parent, title, row_fns):
        outer = tk.Frame(parent, bg=SURFACE,
                         highlightbackground=BORDER, highlightthickness=1)
        outer.pack(fill="x", pady=(0, 10))

        tk.Label(outer, text=title, bg=SURFACE, fg=ACCENT,
                 font=("Sans", 9, "bold")).pack(anchor="w", padx=14, pady=(10, 6))
        tk.Frame(outer, bg=BORDER, height=1).pack(fill="x", padx=14)

        for fn in row_fns:
            fn(outer)

    # ── row types ─────────────────────────────────────────────────────────────

    def _row_frame(self, parent):
        """Base two-column row frame inside a card."""
        f = tk.Frame(parent, bg=SURFACE)
        f.pack(fill="x", padx=14, pady=10)
        tk.Frame(parent, bg=BORDER, height=1).pack(fill="x", padx=14)
        return f

    def _row_labels(self, frame, label, hint):
        left = tk.Frame(frame, bg=SURFACE)
        left.pack(side="left", fill="x", expand=True)
        tk.Label(left, text=label, bg=SURFACE, fg=TEXT,
                 font=("Sans", 11), anchor="w").pack(anchor="w")
        tk.Label(left, text=hint, bg=SURFACE, fg=SUBTEXT,
                 font=("Sans", 9), anchor="w").pack(anchor="w")

    def _row_check(self, parent, label, hint, var):
        f = self._row_frame(parent)
        self._row_labels(f, label, hint)
        tk.Checkbutton(f, variable=var, bg=SURFACE,
                       activebackground=SURFACE, selectcolor=BORDER,
                       relief="flat", command=self._mark_dirty,
                       ).pack(side="right")

    def _row_spin(self, parent, label, hint, var, lo=0, hi=120):
        f = self._row_frame(parent)
        self._row_labels(f, label, hint)
        sp = tk.Spinbox(f, from_=lo, to=hi, textvariable=var, width=5,
                        bg=BORDER, fg=TEXT, insertbackground=TEXT,
                        buttonbackground=BORDER, relief="flat",
                        command=self._mark_dirty)
        sp.bind("<KeyRelease>", lambda _: self._mark_dirty())
        sp.pack(side="right")

    def _row_default(self, parent):
        f = self._row_frame(parent)
        if self.entries:
            self._row_labels(f, "Which operating system starts by default?",
                             "Shown when the boot menu appears")
            cb = ttk.Combobox(f, textvariable=self._var_default,
                              values=self.entries, state="readonly", width=34)
            cb.bind("<<ComboboxSelected>>", lambda _: self._mark_dirty())
            cb.pack(side="right")
        else:
            self._row_labels(f, "Which operating system starts by default?",
                             "0 = first entry, 1 = second…  (entry names unreadable without root)")
            sp = tk.Spinbox(f, from_=0, to=9,
                            textvariable=self._var_default_idx,
                            width=4, bg=BORDER, fg=TEXT,
                            insertbackground=TEXT, buttonbackground=BORDER,
                            relief="flat", command=self._mark_dirty)
            sp.bind("<KeyRelease>", lambda _: self._mark_dirty())
            tk.Label(f, text="entry #", bg=SURFACE, fg=SUBTEXT,
                     font=("Sans", 9)).pack(side="right", padx=(0, 4))
            sp.pack(side="right")

    # ── load / collect ────────────────────────────────────────────────────────

    def _load(self):
        cfg     = self.cfg
        default = cfg.get("GRUB_DEFAULT", "0")

        if default == "saved":
            self._var_saved.set(True)
        else:
            self._var_saved.set(False)
            if self.entries:
                try:
                    idx = int(default)
                    self._var_default.set(
                        self.entries[min(idx, len(self.entries) - 1)])
                except (ValueError, IndexError):
                    self._var_default.set(
                        default if default in self.entries else self.entries[0])
            else:
                try:
                    self._var_default_idx.set(int(default))
                except ValueError:
                    self._var_default_idx.set(0)

        try:
            self._var_timeout.set(int(cfg.get("GRUB_TIMEOUT", "5")))
        except ValueError:
            self._var_timeout.set(5)

        self._var_hidden.set(cfg.get("GRUB_TIMEOUT_STYLE", "menu") == "hidden")

        cmdline = cfg.get("GRUB_CMDLINE_LINUX_DEFAULT", "quiet splash")
        self._var_quiet.set("quiet"  in cmdline)
        self._var_splash.set("splash" in cmdline)

        self._var_recovery.set(
            cfg.get("GRUB_DISABLE_RECOVERY", "false").lower() != "true")

        self._set_status("idle", "No unsaved changes")

    def _collect(self):
        cfg = dict(self.cfg)

        if self._var_saved.get():
            cfg["GRUB_DEFAULT"]     = "saved"
            cfg["GRUB_SAVEDEFAULT"] = "true"
        else:
            if self.entries:
                sel = self._var_default.get()
                idx = self.entries.index(sel) if sel in self.entries else 0
            else:
                idx = self._var_default_idx.get()
            cfg["GRUB_DEFAULT"]     = str(idx)
            cfg["GRUB_SAVEDEFAULT"] = "false"

        cfg["GRUB_TIMEOUT"]       = str(self._var_timeout.get())
        cfg["GRUB_TIMEOUT_STYLE"] = "hidden" if self._var_hidden.get() else "menu"

        parts  = (["quiet"]  if self._var_quiet.get()  else []) + \
                 (["splash"] if self._var_splash.get() else [])
        extras = [w for w in cfg.get("GRUB_CMDLINE_LINUX_DEFAULT", "").split()
                  if w not in ("quiet", "splash")]
        cfg["GRUB_CMDLINE_LINUX_DEFAULT"] = " ".join(parts + extras)

        cfg["GRUB_DISABLE_RECOVERY"] = (
            "false" if self._var_recovery.get() else "true")
        return cfg

    def _mark_dirty(self):
        self._set_status("idle", "Unsaved changes")

    # ── apply ─────────────────────────────────────────────────────────────────

    def _on_apply(self):
        if not messagebox.askokcancel(
            "Apply boot changes?",
            "This will update the boot configuration and run update-grub.\n"
            "You will be asked for your password.\n\n"
            "Changes take effect on next startup.",
            parent=self
        ):
            return
        try:
            tmp = write_grub_cfg_to_tmp(self._collect())
        except Exception as e:
            self._set_status("err", f"Failed to prepare config: {e}")
            return
        self._set_status("idle", "Waiting for authentication…")
        self.after(50, lambda: self._do_apply(tmp))

    def _do_apply(self, tmp):
        ok, msg = apply_via_pkexec(tmp)
        self._set_status("ok" if ok else "err", msg)

    def _set_status(self, kind, msg):
        colour = {"ok": GREEN, "err": RED}.get(kind, SUBTEXT)
        prefix = {"ok": "✓ ", "err": "✗ "}.get(kind, "")
        short  = msg[:90] + "…" if len(msg) > 90 else msg
        self._status_var.set(prefix + short)
        self._status_lbl.configure(fg=colour)


if __name__ == "__main__":
    GrubManager().mainloop()
