#!/usr/bin/env python3
"""
grub-manager.py — GRUB configuration GUI for Ubuntu 24.04
Runs as normal user. Elevates only at save time via pkexec helper.
Requires: python3-tk  (sudo apt install python3-tk)
"""

import os, re, subprocess, tempfile
from pathlib import Path
import tkinter as tk
import tkinter.font as tkfont
from tkinter import ttk, messagebox

GRUB_CFG  = Path("/etc/default/grub")
APPLY_BIN = "/usr/local/bin/grub-manager-apply"

BG      = "#1e1e2e"
SURFACE = "#181825"
BORDER  = "#45475a"
TEXT    = "#cdd6f4"
SUBTEXT = "#a6adc8"
MUTED   = "#6c7086"
ACCENT  = "#cba6f7"
GREEN   = "#a6e3a1"
RED     = "#f38ba8"
YELLOW  = "#f9e2af"
BTN_BG  = "#313244"
BTN_HOV = "#45475a"

BASE_W = 720

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
        return False, f"Helper not installed — run: sudo bash install.sh"
    try:
        r = subprocess.run(["pkexec", APPLY_BIN, tmp_path],
                           capture_output=True, text=True, timeout=60)
        out = (r.stdout + r.stderr).strip()
        return r.returncode == 0, out or ("Done." if r.returncode == 0 else "Unknown error")
    except subprocess.TimeoutExpired:
        return False, "Timed out waiting for update-grub"
    except FileNotFoundError:
        return False, "pkexec not found — is policykit-1 installed?"
    except Exception as e:
        return False, str(e)

# ── Toggle widget ─────────────────────────────────────────────────────────────

class Toggle(tk.Frame):
    """Pill-shaped ON/OFF toggle."""
    def __init__(self, parent, variable, command=None, size=28, **kw):
        super().__init__(parent, bg=kw.pop("bg", SURFACE), **kw)
        self._var  = variable
        self._cmd  = command
        self._size = size
        self._cv   = tk.Canvas(self, highlightthickness=0, cursor="hand2",
                               bg=self["bg"])
        self._cv.pack()
        self.resize(size)
        self._var.trace_add("write", lambda *_: self._draw())
        for seq in ("<Button-1>", "<Return>", "<space>"):
            self._cv.bind(seq, self._toggle)
        self._cv.configure(takefocus=True)
        self._cv.bind("<FocusIn>",  lambda _: self._draw())
        self._cv.bind("<FocusOut>", lambda _: self._draw())

    def resize(self, size):
        self._size = size
        w = int(size * 1.93)
        self._cv.configure(width=w, height=size)
        self._draw()

    def _draw(self):
        c = self._cv; c.delete("all")
        H   = self._size
        W   = int(H * 1.93)
        PAD = max(2, H // 10)
        on  = bool(self._var.get())
        foc = c.focus_get() == c
        trk = GREEN if on else BTN_BG
        if foc:
            c.create_rectangle(1, 1, W-2, H-2, outline=ACCENT, width=2)
        r = H // 2 - PAD
        for cx in (PAD + r, W - PAD - r):
            c.create_oval(cx-r, PAD, cx+r, H-PAD, fill=trk, outline="")
        c.create_rectangle(PAD+r, PAD, W-PAD-r, H-PAD, fill=trk, outline="")
        kx = W - PAD - r if on else PAD + r
        c.create_oval(kx-r+2, PAD+2, kx+r-2, H-PAD-2, fill=TEXT, outline="")
        lx = PAD + r//2 + 2 if on else W - PAD - r//2 - 2
        fs = max(6, H // 4)
        c.create_text(lx, H//2, text="ON" if on else "OFF",
                      fill=BG if on else MUTED,
                      font=("Sans", fs, "bold"))

    def _toggle(self, _=None):
        self._var.set(not self._var.get())
        if self._cmd: self._cmd()

# ── boot icon ─────────────────────────────────────────────────────────────────

def make_boot_icon(size=32):
    import math
    img = tk.PhotoImage(width=size, height=size)
    s   = size / 32.0

    def px(x, y, c):
        xi, yi = int(x), int(y)
        if 0 <= xi < size and 0 <= yi < size:
            img.put(c, (xi, yi))

    def rect(x1, y1, x2, y2, c):
        for y in range(int(y1), int(y2)+1):
            for x in range(int(x1), int(x2)+1):
                px(x, y, c)

    def circle(cx, cy, r, c):
        for y in range(int(cy-r), int(cy+r)+1):
            for x in range(int(cx-r), int(cx+r)+1):
                if math.hypot(x-cx, y-cy) <= r:
                    px(x, y, c)

    rect(0, 0, size-1, size-1, BG)
    rect(3*s, 8*s, 29*s, 24*s, "#585b70")
    rect(4*s, 9*s, 28*s, 23*s, "#45475a")
    circle(16*s, 16*s, 5*s, "#313244")
    circle(16*s, 16*s, 2*s, "#7f849c")
    rect(22*s, 21*s, 27*s, 23*s, "#313244")
    circle(7*s, 11*s, 1.5*s, GREEN)
    for y in range(int(10*s), int(22*s)+1):
        half = 6*s
        dist = abs(y - 16*s)
        reach = (half - dist) * (8*s / half)
        for x in range(int(18*s), int(18*s + reach)+1):
            px(x, y, ACCENT)
    return img

# ── main window ───────────────────────────────────────────────────────────────

class GrubManager(tk.Tk):

    # base sizes — _rescale multiplies these by scale factor
    _BASE = dict(
        h1=15, sub=10, lbl=11, hnt=9, crd=9, btn=11, mon=10,
        btn_padx=16, btn_pady=6, toggle=28, row_pady=10,
    )

    def __init__(self):
        super().__init__()
        self.title("Boot Options Manager")
        self.configure(bg=BG)
        self.resizable(True, True)
        self.minsize(560, 460)

        self.cfg     = read_grub_cfg()
        self.entries = get_boot_entries()
        self._raw_default = self.cfg.get("GRUB_DEFAULT", "0")
        self._raw_cmdline = self.cfg.get("GRUB_CMDLINE_LINUX_DEFAULT", "quiet splash")
        self._scale        = 1.0
        self._resize_job   = None

        # Font objects — updating these auto-updates every widget using them
        self._F = {
            "h1":  tkfont.Font(family="Sans", size=15, weight="bold"),
            "sub": tkfont.Font(family="Sans", size=10),
            "lbl": tkfont.Font(family="Sans", size=11),
            "hnt": tkfont.Font(family="Sans", size=9),
            "crd": tkfont.Font(family="Sans", size=9,  weight="bold"),
            "btn": tkfont.Font(family="Sans", size=11, weight="bold"),
            "mon": tkfont.Font(family="Monospace", size=10),
        }

        # Registries for widgets needing explicit non-font updates on resize
        self._toggle_widgets = []   # Toggle instances
        self._button_widgets = []   # tk.Button instances
        self._row_frames     = []   # (frame, parent) for row vertical padding
        self._spin_widgets   = []   # tk.Spinbox instances

        # Tk vars
        self._var_default     = tk.StringVar()
        self._var_default_idx = tk.IntVar(value=0)
        self._var_timeout     = tk.IntVar(value=5)
        self._var_hidden      = tk.BooleanVar()
        self._var_quiet       = tk.BooleanVar()
        self._var_splash      = tk.BooleanVar()
        self._var_saved       = tk.BooleanVar()
        self._var_recovery    = tk.BooleanVar()
        self._status_var      = tk.StringVar(value="")
        self._cmdline_lbl     = tk.StringVar()
        self._dirty           = False

        self._build()
        self._load()

        self.update_idletasks()
        try:
            self._icon = make_boot_icon(32)
            self.iconphoto(True, self._icon)
        except Exception:
            pass

        w = max(720, self.winfo_reqwidth())
        h = max(580, self.winfo_reqheight())
        sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
        self.geometry(f"{w}x{h}+{(sw-w)//2}+{(sh-h)//2}")

        self.bind("<Configure>", self._on_configure)

    # ── responsive scaling ────────────────────────────────────────────────────

    def _on_configure(self, event):
        if event.widget is not self:
            return
        if self._resize_job:
            self.after_cancel(self._resize_job)
        self._resize_job = self.after(60, lambda: self._rescale(event.width))

    def _rescale(self, width):
        scale = max(0.75, min(2.2, width / BASE_W))
        if abs(scale - self._scale) < 0.03:
            return
        self._scale = scale

        def s(key):
            return max(7, int(self._BASE[key] * scale))

        # 1. Font objects — every Label/Entry/etc using these updates automatically
        self._F["h1" ].configure(size=s("h1"))
        self._F["sub"].configure(size=s("sub"))
        self._F["lbl"].configure(size=s("lbl"))
        self._F["hnt"].configure(size=s("hnt"))
        self._F["crd"].configure(size=s("crd"))
        self._F["btn"].configure(size=s("btn"))
        self._F["mon"].configure(size=s("mon"))

        # 2. Button padding — font scaling alone won't grow the button frame
        px_ = max(6, int(self._BASE["btn_padx"] * scale))
        py_ = max(4, int(self._BASE["btn_pady"] * scale))
        for b in self._button_widgets:
            try:
                b.configure(padx=px_, pady=py_)
            except tk.TclError:
                pass

        # 3. Toggle size
        tsz = max(20, int(self._BASE["toggle"] * scale))
        for t in self._toggle_widgets:
            try:
                t.resize(tsz)
            except Exception:
                pass

        # 4. Row vertical padding
        rpy = max(4, int(self._BASE["row_pady"] * scale))
        for f in self._row_frames:
            try:
                f.pack_configure(pady=rpy)
            except tk.TclError:
                pass

    # ── build ─────────────────────────────────────────────────────────────────

    def _build(self):
        F  = self._F
        st = ttk.Style(self)
        st.theme_use("clam")
        st.configure("TSeparator", background=BORDER)
        st.configure("TCombobox",
                     fieldbackground=BTN_BG, background=BTN_BG,
                     foreground=TEXT, selectbackground=BTN_BG,
                     selectforeground=TEXT, arrowcolor=TEXT,
                     bordercolor=BORDER, lightcolor=BTN_BG, darkcolor=BTN_BG)
        st.map("TCombobox",
               fieldbackground=[("readonly", BTN_BG), ("focus", BTN_BG)],
               foreground=[("readonly", TEXT)],
               bordercolor=[("focus", ACCENT)])

        # header
        hdr = tk.Frame(self, bg=SURFACE)
        hdr.pack(fill="x")
        tk.Label(hdr, text="Boot Options Manager",
                 bg=SURFACE, fg=TEXT, font=F["h1"]
                 ).pack(anchor="w", padx=20, pady=(14, 2))
        tk.Label(hdr, text="Configure GRUB — changes take effect on next startup",
                 bg=SURFACE, fg=SUBTEXT, font=F["sub"]
                 ).pack(anchor="w", padx=20, pady=(0, 12))
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # body
        body = tk.Frame(self, bg=BG)
        body.pack(fill="both", expand=True, padx=18, pady=14)

        c1 = self._card(body, "🖥   DEFAULT BOOT SELECTION")
        self._row_default(c1)

        c2 = self._card(body, "⏱   MENU TIMING")
        self._row_spin(c2,
            "Seconds to display the boot menu",
            "0 = skip menu and boot immediately  |  −1 = wait forever",
            self._var_timeout, lo=-1, hi=120)
        self._row_toggle(c2,
            "Hide boot menu on startup",
            "Hold  Shift  at power-on to force the menu to appear",
            self._var_hidden)

        c3 = self._card(body, "🔧   BOOT BEHAVIOUR")
        self._row_toggle(c3,
            "Suppress verbose boot messages",
            "ON = quiet boot (recommended)  |  OFF = show all kernel output",
            self._var_quiet)
        self._row_toggle(c3,
            "Show graphical splash screen",
            "Display the Ubuntu logo while booting",
            self._var_splash)
        self._row_toggle(c3,
            "Remember last OS selected",
            "GRUB will auto-select whichever OS you booted last time",
            self._var_saved)
        tk.Label(c3, textvariable=self._cmdline_lbl,
                 bg=SURFACE, fg=MUTED, font=F["mon"],
                 anchor="w", padx=14).pack(fill="x", pady=(0, 8))

        c4 = self._card(body, "🛟   RECOVERY")
        self._row_toggle(c4,
            "Show recovery options in boot menu",
            "Adds a recovery entry — useful if you need to repair the system",
            self._var_recovery)

        # footer
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")
        foot = tk.Frame(self, bg=BG)
        foot.pack(fill="x")

        self._status_lbl = tk.Label(foot, textvariable=self._status_var,
                                    bg=BG, fg=MUTED, font=F["hnt"],
                                    anchor="w", wraplength=380, justify="left")
        self._status_lbl.pack(side="left", padx=18, pady=10)

        btn_frame = tk.Frame(foot, bg=BG)
        btn_frame.pack(side="right", padx=14, pady=8)

        self._cancel_btn = tk.Button(
            btn_frame, text="Cancel", command=self._on_cancel,
            bg=BTN_BG, fg=TEXT, font=F["btn"], relief="flat",
            padx=16, pady=6, cursor="hand2",
            activebackground=BTN_HOV, activeforeground=TEXT, width=8)
        self._cancel_btn.pack(side="left", padx=(0, 8))
        self._button_widgets.append(self._cancel_btn)

        self._apply_btn = tk.Button(
            btn_frame, text="Save & Apply", command=self._on_apply,
            bg=ACCENT, fg=BG, font=F["btn"], relief="flat",
            padx=16, pady=6, cursor="hand2",
            activebackground="#b4befe", activeforeground=BG)
        self._apply_btn.pack(side="left")
        self._button_widgets.append(self._apply_btn)

        self.bind("<Escape>",         lambda _: self._on_cancel())
        self.bind("<Control-s>",      lambda _: self._on_apply())
        self.bind("<Control-Return>", lambda _: self._on_apply())
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── card ──────────────────────────────────────────────────────────────────

    def _card(self, parent, title):
        frame = tk.Frame(parent, bg=SURFACE,
                         highlightbackground=BORDER, highlightthickness=1)
        frame.pack(fill="x", pady=(0, 10))
        tk.Label(frame, text=title, bg=SURFACE, fg=ACCENT,
                 font=self._F["crd"]
                 ).pack(anchor="w", padx=14, pady=(10, 6))
        tk.Frame(frame, bg=BORDER, height=1).pack(fill="x", padx=14)
        return frame

    # ── row helpers ───────────────────────────────────────────────────────────

    def _row_frame(self, parent):
        f = tk.Frame(parent, bg=SURFACE)
        f.pack(fill="x", padx=14, pady=10)
        self._row_frames.append(f)
        tk.Frame(parent, bg=BORDER, height=1).pack(fill="x", padx=14)
        return f

    def _row_left(self, frame, label, hint):
        left = tk.Frame(frame, bg=SURFACE)
        left.pack(side="left", fill="x", expand=True)
        tk.Label(left, text=label, bg=SURFACE, fg=TEXT,
                 font=self._F["lbl"], anchor="w").pack(anchor="w")
        tk.Label(left, text=hint, bg=SURFACE, fg=SUBTEXT,
                 font=self._F["hnt"], anchor="w",
                 wraplength=480, justify="left").pack(anchor="w")

    def _row_toggle(self, parent, label, hint, var):
        f = self._row_frame(parent)
        self._row_left(f, label, hint)
        t = Toggle(f, variable=var, command=self._mark_dirty,
                   size=28, bg=SURFACE)
        t.pack(side="right", padx=(12, 0))
        self._toggle_widgets.append(t)

    def _row_spin(self, parent, label, hint, var, lo=0, hi=120):
        f = self._row_frame(parent)
        self._row_left(f, label, hint)
        sp = tk.Spinbox(f, from_=lo, to=hi, textvariable=var, width=5,
                        bg=BTN_BG, fg=TEXT, insertbackground=TEXT,
                        buttonbackground=BTN_BG, relief="flat",
                        font=self._F["lbl"], command=self._mark_dirty)
        sp.bind("<KeyRelease>", lambda _: self._mark_dirty())
        sp.pack(side="right", padx=(12, 0))
        self._spin_widgets.append(sp)

    def _row_default(self, parent):
        f = self._row_frame(parent)
        raw = self._raw_default

        if self.entries:
            try:
                current_name = self.entries[int(raw)]
            except (ValueError, IndexError):
                current_name = raw if raw in self.entries else self.entries[0]
            if raw == "saved":
                current_name = "(last chosen — GRUB_SAVEDEFAULT)"
            self._row_left(f, "Default operating system",
                           f"Currently:  {current_name}")
            cb = ttk.Combobox(f, textvariable=self._var_default,
                              values=self.entries, state="readonly", width=36,
                              font=self._F["lbl"])
            cb.bind("<<ComboboxSelected>>", lambda _: self._mark_dirty())
            cb.pack(side="right", padx=(12, 0))
        else:
            self._row_left(f, "Default operating system (entry number)",
                           f"Currently set to entry #{raw}   "
                           "(run  sudo bash install.sh  once to show OS names)\n"
                           "0 = first entry, 1 = second, etc.")
            right = tk.Frame(f, bg=SURFACE)
            right.pack(side="right", padx=(12, 0))
            tk.Label(right, text="Entry #", bg=SURFACE, fg=SUBTEXT,
                     font=self._F["hnt"]).pack(side="left", padx=(0, 4))
            sp = tk.Spinbox(right, from_=0, to=9,
                            textvariable=self._var_default_idx,
                            width=3, bg=BTN_BG, fg=TEXT,
                            insertbackground=TEXT, buttonbackground=BTN_BG,
                            relief="flat", font=self._F["lbl"],
                            command=self._mark_dirty)
            sp.bind("<KeyRelease>", lambda _: self._mark_dirty())
            sp.pack(side="left")
            self._spin_widgets.append(sp)

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

        self._cmdline_lbl.set(f"Kernel flags:  {cmdline or '(none)'}")
        self._dirty = False
        self._set_status("idle", "No unsaved changes  —  Ctrl+S to save")

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
        cmdline = " ".join(parts + extras)
        cfg["GRUB_CMDLINE_LINUX_DEFAULT"] = cmdline
        self._cmdline_lbl.set(f"Kernel flags:  {cmdline or '(none)'}")

        cfg["GRUB_DISABLE_RECOVERY"] = "false" if self._var_recovery.get() else "true"
        return cfg

    def _mark_dirty(self):
        self._dirty = True
        self._collect()
        self._set_status("warn", "Unsaved changes  —  Ctrl+S or click Save & Apply")

    # ── apply / cancel / close ────────────────────────────────────────────────

    def _on_apply(self):
        if not messagebox.askokcancel(
            "Apply boot changes?",
            "This will overwrite /etc/default/grub and run update-grub.\n"
            "A backup is saved to /etc/default/grub.bak\n\n"
            "You will be asked for your password.\n"
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
        self._apply_btn.configure(state="disabled")
        self._cancel_btn.configure(state="disabled")
        self.after(50, lambda: self._do_apply(tmp))

    def _do_apply(self, tmp):
        ok, msg = apply_via_pkexec(tmp)
        self._apply_btn.configure(state="normal")
        self._cancel_btn.configure(state="normal")
        if ok:
            self._dirty  = False
            self.cfg     = read_grub_cfg()
            self.entries = get_boot_entries()
        self._set_status("ok" if ok else "err", msg)

    def _on_cancel(self):
        if self._dirty:
            if not messagebox.askokcancel(
                "Discard changes?",
                "You have unsaved changes. Revert to saved settings?",
                parent=self
            ):
                return
        self._load()

    def _on_close(self):
        if self._dirty:
            if not messagebox.askokcancel(
                "Unsaved changes",
                "You have unsaved changes. Close without saving?",
                parent=self
            ):
                return
        self.destroy()

    def _set_status(self, kind, msg):
        colour = {"ok": GREEN, "err": RED, "warn": YELLOW}.get(kind, MUTED)
        prefix = {"ok": "✓  ", "err": "✗  ", "warn": "●  "}.get(kind, "")
        self._status_var.set(prefix + msg)
        self._status_lbl.configure(fg=colour)


if __name__ == "__main__":
    GrubManager().mainloop()
