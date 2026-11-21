#!/usr/bin/env bash
set -e

APP_DIR="/opt/shieldguard"
DESKTOP_FILE="/usr/share/applications/shieldguard.desktop"
POLKIT_FILE="/usr/share/polkit-1/actions/org.shieldguard.firewall.policy"

if [[ $EUID -ne 0 ]]; then
   echo "Please run this installer as root: sudo bash install.sh"
   exit 1
fi

echo "===================================================="
echo " Installing ShieldGuard Firewall Manager v1.0.0"
echo " Built by Rajneesh Kumar Yadav"
echo "===================================================="

echo "[1/5] Installing system dependencies (python3-tk, nftables, policykit)..."
apt-get update -qq
apt-get install -y -qq python3 python3-tk nftables policykit-1

echo "[2/5] Enabling nftables service..."
systemctl enable --now nftables >/dev/null 2>&1 || true

echo "[3/5] Deploying application to ${APP_DIR}..."
mkdir -p "${APP_DIR}"

cat << 'EOF' > "${APP_DIR}/firewall_gui.py"
#!/usr/bin/env python3
"""
ShieldGuard Firewall Manager
Built by Rajneesh Kumar Yadav
"""

import os
import subprocess
import threading
import urllib.request
import ipaddress
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

# ==========================================
# BRANDING CONFIGURATION
# ==========================================
APP_NAME = "ShieldGuard Firewall Manager"
OWNER_NAME = "Rajneesh Kumar Yadav"
APP_VERSION = "1.0.0"

# Embedded Shield Logo (64x64 PNG Base64)
SHIELD_ICON_B64 = (
    "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"
)
# ==========================================

CONFIG_DIR = "/etc/firewall_manager_nft"
NFT_RULES_DIR = "/etc/nftables.d"
OUR_RULES_FILE = os.path.join(NFT_RULES_DIR, "firewall-manager.nft")

FILES = {
    "in_tcp": os.path.join(CONFIG_DIR, "allowed_tcp_ports.conf"),
    "in_udp": os.path.join(CONFIG_DIR, "allowed_udp_ports.conf"),
    "out_tcp": os.path.join(CONFIG_DIR, "allowed_node_tcp_ports.conf"),
    "out_udp": os.path.join(CONFIG_DIR, "allowed_node_udp_ports.conf"),
    "blocked": os.path.join(CONFIG_DIR, "blocked_ips.conf"),
}

BLOCKLIST_URL = "https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4"


class FirewallGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION} — {OWNER_NAME}")
        self.geometry("860x650")
        self.minsize(780, 540)

        try:
            self.app_icon = tk.PhotoImage(data=SHIELD_ICON_B64)
            self.iconphoto(True, self.app_icon)
            self.header_icon = self.app_icon.subsample(2, 2)
        except Exception:
            self.app_icon = None
            self.header_icon = None

        if os.geteuid() != 0:
            messagebox.showwarning(
                "Root Privileges Required",
                "Please run this application with sudo or pkexec to manage nftables rules."
            )

        self.ensure_config_dir()
        self.ensure_ssh_port()
        self.create_widgets()
        self.refresh_all_lists()

    def ensure_config_dir(self):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        os.makedirs(NFT_RULES_DIR, exist_ok=True)
        for path in FILES.values():
            if not os.path.exists(path):
                open(path, "w").close()

    def detect_ssh_port(self):
        try:
            out = subprocess.check_output(["sshd", "-T"], stderr=subprocess.DEVNULL, text=True)
            for line in out.splitlines():
                if line.startswith("port "):
                    parts = line.split()
                    if len(parts) >= 2 and parts[1].isdigit():
                        port = int(parts[1])
                        if 1 <= port <= 65535:
                            return str(port)
        except Exception:
            pass
        return "22"

    def ensure_ssh_port(self):
        ssh_port = self.detect_ssh_port()
        ports = self.read_lines(FILES["in_tcp"])
        if ssh_port not in ports:
            ports.append(ssh_port)
            self.write_lines(FILES["in_tcp"], sorted(set(ports), key=int))

    def read_lines(self, filepath):
        if not os.path.exists(filepath):
            return []
        with open(filepath, "r") as f:
            return [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    def write_lines(self, filepath, lines):
        with open(filepath, "w") as f:
            f.write(f"# Managed by {APP_NAME} ({OWNER_NAME})\n")
            for item in lines:
                f.write(f"{item}\n")

    def create_widgets(self):
        header_frame = tk.Frame(self, bg="#0f172a", pady=10, padx=15)
        header_frame.pack(fill=tk.X)

        if self.header_icon:
            tk.Label(header_frame, image=self.header_icon, bg="#0f172a").pack(side=tk.LEFT, padx=(0, 10))

        tk.Label(
            header_frame,
            text=APP_NAME,
            font=("Sans", 15, "bold"),
            fg="#f8fafc",
            bg="#0f172a"
        ).pack(side=tk.LEFT)

        tk.Label(
            header_frame,
            text=f"v{APP_VERSION}  |  Built by {OWNER_NAME}",
            font=("Sans", 9),
            fg="#94a3b8",
            bg="#0f172a"
        ).pack(side=tk.RIGHT, pady=(4, 0))

        top_frame = ttk.Frame(self, padding=10)
        top_frame.pack(fill=tk.X)

        ttk.Button(top_frame, text="Apply & Persist Rules", command=self.apply_rules).pack(side=tk.LEFT, padx=5)
        ttk.Button(top_frame, text="Refresh Active Rules", command=self.load_active_rules).pack(side=tk.LEFT, padx=5)
        ttk.Button(top_frame, text="Flush Firewall Table", command=self.flush_rules).pack(side=tk.RIGHT, padx=5)

        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(top_frame, textvariable=self.status_var, foreground="#0284c7").pack(side=tk.LEFT, padx=15)

        notebook = ttk.Notebook(self)
        notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 5))

        self.tab_rules = ttk.Frame(notebook, padding=10)
        notebook.add(self.tab_rules, text="Active Ruleset")
        self.rules_text = scrolledtext.ScrolledText(self.tab_rules, wrap=tk.NONE, font=("Monospace", 10))
        self.rules_text.pack(fill=tk.BOTH, expand=True)

        self.tab_inbound = ttk.Frame(notebook, padding=10)
        notebook.add(self.tab_inbound, text="Inbound Ports")
        self.build_port_manager(self.tab_inbound, "in_tcp", "in_udp", "Inbound")

        self.tab_outbound = ttk.Frame(notebook, padding=10)
        notebook.add(self.tab_outbound, text="Outbound / Node Ports")
        self.build_port_manager(self.tab_outbound, "out_tcp", "out_udp", "Outbound")

        self.tab_blocklist = ttk.Frame(notebook, padding=10)
        notebook.add(self.tab_blocklist, text="IP Blocklist")
        self.build_blocklist_manager(self.tab_blocklist)

        footer = ttk.Label(
            self,
            text=f"{APP_NAME} • Local System Security Console • {OWNER_NAME}",
            font=("Sans", 8),
            foreground="#64748b"
        )
        footer.pack(side=tk.BOTTOM, pady=(0, 6))

    def build_port_manager(self, parent, tcp_key, udp_key, label_prefix):
        parent.columnconfigure(0, weight=1)
        parent.columnconfigure(1, weight=1)
        parent.rowconfigure(1, weight=1)

        tcp_frame = ttk.LabelFrame(parent, text=f"{label_prefix} TCP Ports", padding=10)
        tcp_frame.grid(row=0, column=0, rowspan=2, sticky="nsew", padx=(0, 5))

        tcp_list = tk.Listbox(tcp_frame, selectmode=tk.EXTENDED)
        tcp_list.pack(fill=tk.BOTH, expand=True, pady=(0, 5))
        setattr(self, f"{tcp_key}_listbox", tcp_list)

        tcp_entry = ttk.Entry(tcp_frame)
        tcp_entry.pack(fill=tk.X, pady=(0, 5))
        ttk.Label(tcp_frame, text="Format: 80, 443, or 8000-8010", font=("Sans", 8)).pack(anchor=tk.W)

        btn_frame_tcp = ttk.Frame(tcp_frame)
        btn_frame_tcp.pack(fill=tk.X, pady=5)
        ttk.Button(btn_frame_tcp, text="Add", command=lambda: self.add_ports(tcp_key, tcp_entry)).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 2))
        ttk.Button(btn_frame_tcp, text="Remove Selected", command=lambda: self.remove_selected_ports(tcp_key, tcp_list)).pack(side=tk.RIGHT, expand=True, fill=tk.X, padx=(2, 0))

        udp_frame = ttk.LabelFrame(parent, text=f"{label_prefix} UDP Ports", padding=10)
        udp_frame.grid(row=0, column=1, rowspan=2, sticky="nsew", padx=(5, 0))

        udp_list = tk.Listbox(udp_frame, selectmode=tk.EXTENDED)
        udp_list.pack(fill=tk.BOTH, expand=True, pady=(0, 5))
        setattr(self, f"{udp_key}_listbox", udp_list)

        udp_entry = ttk.Entry(udp_frame)
        udp_entry.pack(fill=tk.X, pady=(0, 5))
        ttk.Label(udp_frame, text="Format: 53, 51820, or 10000-20000", font=("Sans", 8)).pack(anchor=tk.W)

        btn_frame_udp = ttk.Frame(udp_frame)
        btn_frame_udp.pack(fill=tk.X, pady=5)
        ttk.Button(btn_frame_udp, text="Add", command=lambda: self.add_ports(udp_key, udp_entry)).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 2))
        ttk.Button(btn_frame_udp, text="Remove Selected", command=lambda: self.remove_selected_ports(udp_key, udp_list)).pack(side=tk.RIGHT, expand=True, fill=tk.X, padx=(2, 0))

    def build_blocklist_manager(self, parent):
        ctrl_frame = ttk.Frame(parent)
        ctrl_frame.pack(fill=tk.X, pady=(0, 5))

        self.ip_entry = ttk.Entry(ctrl_frame)
        self.ip_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 5))

        ttk.Button(ctrl_frame, text="Add IP/CIDR", command=self.add_blocked_ip).pack(side=tk.LEFT, padx=2)
        ttk.Button(ctrl_frame, text="Remove Selected", command=self.remove_blocked_ip).pack(side=tk.LEFT, padx=2)
        ttk.Button(ctrl_frame, text="Sync Remote Blocklist", command=self.update_remote_blocklist).pack(side=tk.RIGHT, padx=2)

        self.block_count_var = tk.StringVar(value="Blocked entries: 0")
        ttk.Label(parent, textvariable=self.block_count_var).pack(anchor=tk.W, pady=(0, 5))

        self.ip_listbox = tk.Listbox(parent, selectmode=tk.EXTENDED, font=("Monospace", 10))
        self.ip_listbox.pack(fill=tk.BOTH, expand=True)

    def refresh_all_lists(self):
        for key in ["in_tcp", "in_udp", "out_tcp", "out_udp"]:
            lb = getattr(self, f"{key}_listbox")
            lb.delete(0, tk.END)
            ports = sorted(set(self.read_lines(FILES[key])), key=lambda x: int(x) if x.isdigit() else 0)
            for p in ports:
                lb.insert(tk.END, p)

        self.ip_listbox.delete(0, tk.END)
        ips = sorted(set(self.read_lines(FILES["blocked"])))
        self.block_count_var.set(f"Blocked entries: {len(ips)} (showing up to 500)")
        for ip in ips[:500]:
            self.ip_listbox.insert(tk.END, ip)

        self.load_active_rules()

    def add_ports(self, file_key, entry_widget):
        raw = entry_widget.get().strip()
        if not raw:
            return
        current = set(self.read_lines(FILES[file_key]))
        items = [x.strip() for x in raw.replace(" ", ",").split(",") if x.strip()]
        for item in items:
            if "-" in item:
                parts = item.split("-")
                if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
                    start, end = int(parts[0]), int(parts[1])
                    if 1 <= start <= end <= 65535:
                        for p in range(start, end + 1):
                            current.add(str(p))
            elif item.isdigit() and 1 <= int(item) <= 65535:
                current.add(str(int(item)))

        self.write_lines(FILES[file_key], sorted(current, key=int))
        entry_widget.delete(0, tk.END)
        self.refresh_all_lists()

    def remove_selected_ports(self, file_key, listbox):
        selected = [listbox.get(i) for i in listbox.curselection()]
        if not selected:
            return
        current = [p for p in self.read_lines(FILES[file_key]) if p not in selected]
        self.write_lines(FILES[file_key], current)
        self.refresh_all_lists()

    def add_blocked_ip(self):
        raw = self.ip_entry.get().strip()
        if not raw:
            return
        current = set(self.read_lines(FILES["blocked"]))
        for item in raw.replace(" ", ",").split(","):
            item = item.strip()
            if not item:
                continue
            try:
                net = ipaddress.IPv4Network(item, strict=False)
                current.add(str(net))
            except ValueError:
                messagebox.showerror("Invalid IP", f"Invalid IPv4 address or CIDR: {item}")
                return
        self.write_lines(FILES["blocked"], sorted(current))
        self.ip_entry.delete(0, tk.END)
        self.refresh_all_lists()

    def remove_blocked_ip(self):
        selected = [self.ip_listbox.get(i) for i in self.ip_listbox.curselection()]
        if not selected:
            return
        current = [ip for ip in self.read_lines(FILES["blocked"]) if ip not in selected]
        self.write_lines(FILES["blocked"], current)
        self.refresh_all_lists()

    def update_remote_blocklist(self):
        self.status_var.set("Downloading blocklist...")
        def worker():
            try:
                req = urllib.request.urlopen(BLOCKLIST_URL, timeout=15)
                lines = req.read().decode("utf-8", errors="ignore").splitlines()
                nets = []
                for line in lines:
                    s = line.strip()
                    if not s or s.startswith("#"):
                        continue
                    try:
                        nets.append(ipaddress.IPv4Network(s, strict=False))
                    except ValueError:
                        pass
                collapsed = [str(n) for n in ipaddress.collapse_addresses(nets)]
                if len(collapsed) > 5:
                    self.write_lines(FILES["blocked"], sorted(set(collapsed)))
                    self.after(0, lambda: self.status_var.set(f"Updated blocklist ({len(collapsed)} CIDRs)."))
                    self.after(0, self.refresh_all_lists)
            except Exception as e:
                self.after(0, lambda: messagebox.showerror("Download Failed", str(e)))
                self.after(0, lambda: self.status_var.set("Blocklist update failed."))
        threading.Thread(target=worker, daemon=True).start()

    def load_active_rules(self):
        self.rules_text.delete("1.0", tk.END)
        try:
            res = subprocess.run(["nft", "list", "table", "inet", "firewall-manager"], capture_output=True, text=True)
            if res.returncode == 0:
                self.rules_text.insert(tk.END, res.stdout)
            else:
                self.rules_text.insert(tk.END, "Table 'inet firewall-manager' is not currently active.\nClick 'Apply & Persist Rules' to activate.")
        except FileNotFoundError:
            self.rules_text.insert(tk.END, "nftables (nft) binary not found on this system.")

    def apply_rules(self):
        self.status_var.set("Applying rules...")
        ssh_port = self.detect_ssh_port()
        self.ensure_ssh_port()

        tcp_in = ",".join([p for p in self.read_lines(FILES["in_tcp"]) if p != ssh_port])
        udp_in = ",".join(self.read_lines(FILES["in_udp"]))
        tcp_out = ",".join(self.read_lines(FILES["out_tcp"]))
        udp_out = ",".join(self.read_lines(FILES["out_udp"]))

        rules = [
            "table inet firewall-manager {",
            "  set blocked_ips { type ipv4_addr; flags interval; }",
            "  set ssh_brute { type ipv4_addr; flags dynamic,timeout; timeout 5m; }",
            "  chain input {",
            "    type filter hook input priority -10; policy drop;",
            "    ct state { established,related } accept",
            "    iif lo accept",
            "    ct state invalid drop",
            "    icmp type { echo-request,echo-reply,destination-unreachable,time-exceeded,parameter-problem } accept",
            "    icmpv6 type { echo-request,echo-reply,destination-unreachable,packet-too-big,time-exceeded,parameter-problem,nd-router-advert,nd-neighbor-solicit,nd-neighbor-advert } accept",
            "    ip saddr @blocked_ips drop",
            "    ip saddr @ssh_brute limit rate over 4/minute burst 5 packets drop",
            f"    tcp dport {ssh_port} ct state new update @ssh_brute {{ ip saddr }}",
            f"    tcp dport {ssh_port} accept",
        ]
        if tcp_in:
            rules.append(f"    tcp dport {{ {tcp_in} }} accept")
            rules.append(f"    ip6 nexthdr tcp tcp dport {{ {tcp_in} }} accept")
        if udp_in:
            rules.append(f"    udp dport {{ {udp_in} }} accept")
            rules.append(f"    ip6 nexthdr udp udp dport {{ {udp_in} }} accept")
        rules.extend([
            '    log prefix "[NFT DROP in] " flags all counter drop',
            "  }",
            "  chain forward {",
            "    type filter hook forward priority -10; policy drop;",
            "    ct state { established,related } accept",
            "    ct state invalid drop",
            "    ip saddr @blocked_ips drop",
            "    ip daddr @blocked_ips drop",
            '    oifname "docker0" accept',
            '    oifname "br-+" accept',
            '    oifname "docker_gwbridge" accept',
            '    oifname "cni-+" accept',
            "    udp dport { 53, 123 } accept",
            "    tcp dport { 80, 443 } accept",
        ])
        if tcp_out:
            rules.append(f"    tcp dport {{ {tcp_out} }} accept")
            rules.append(f"    ip6 nexthdr tcp tcp dport {{ {tcp_out} }} accept")
        if udp_out:
            rules.append(f"    udp dport {{ {udp_out} }} accept")
            rules.append(f"    ip6 nexthdr udp udp dport {{ {udp_out} }} accept")
        rules.extend([
            '    log prefix "[NFT DROP fwd] " flags all counter drop',
            "  }",
            "  chain output {",
            "    type filter hook output priority -10; policy accept;",
            "    ip daddr @blocked_ips drop",
            "  }",
            "}"
        ])

        subprocess.run(["nft", "delete", "table", "inet", "firewall-manager"], stderr=subprocess.DEVNULL)
        proc = subprocess.run(["nft", "-f", "-"], input="\n".join(rules), text=True, capture_output=True)
        if proc.returncode != 0:
            messagebox.showerror("nftables Error", proc.stderr)
            self.status_var.set("Failed to apply rules.")
            return

        blocked = self.read_lines(FILES["blocked"])
        for i in range(0, len(blocked), 200):
            chunk = ",".join(blocked[i:i + 200])
            cmd = f"add element inet firewall-manager blocked_ips {{ {chunk} }}\n"
            subprocess.run(["nft", "-f", "-"], input=cmd, text=True, stderr=subprocess.DEVNULL)

        with open("/etc/nftables.conf", "w") as f:
            f.write(f'#!/usr/sbin/nft -f\n# Generated by {APP_NAME} ({OWNER_NAME})\nflush ruleset\ninclude "/etc/nftables.d/*.nft"\n')

        res = subprocess.run(["nft", "list", "table", "inet", "firewall-manager"], capture_output=True, text=True)
        if res.returncode == 0:
            with open(OUR_RULES_FILE, "w") as f:
                f.write(res.stdout)

        subprocess.run(["systemctl", "reload", "nftables.service"], stderr=subprocess.DEVNULL)
        self.status_var.set("Rules applied and persisted.")
        self.load_active_rules()

    def flush_rules(self):
        if not messagebox.askyesno("Confirm Flush", "Delete the firewall-manager table and persisted rule file?"):
            return
        subprocess.run(["nft", "delete", "table", "inet", "firewall-manager"], stderr=subprocess.DEVNULL)
        if os.path.exists(OUR_RULES_FILE):
            os.remove(OUR_RULES_FILE)
        subprocess.run(["systemctl", "reload", "nftables.service"], stderr=subprocess.DEVNULL)
        self.status_var.set("Firewall rules flushed.")
        self.load_active_rules()


if __name__ == "__main__":
    app = FirewallGUI()
    app.mainloop()
EOF

chmod +x "${APP_DIR}/firewall_gui.py"

echo "[4/5] Extracting embedded shield icon & configuring Polkit..."
python3 -c '
import base64, sys
sys.path.insert(0, "/opt/shieldguard")
import firewall_gui
open("/opt/shieldguard/shieldguard.png", "wb").write(base64.b64decode(firewall_gui.SHIELD_ICON_B64))
'

cat << 'EOF' > "${POLKIT_FILE}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="org.shieldguard.firewall.run">
    <description>Run ShieldGuard Firewall Manager</description>
    <message>Authentication is required to manage system firewall rules</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/python3</annotate>
    <annotate key="org.freedesktop.policykit.exec.allow_gui">true</annotate>
  </action>
</policyconfig>
EOF

echo "[5/5] Creating Applications Menu and Desktop shortcuts..."
cat << 'EOF' > "${DESKTOP_FILE}"
[Desktop Entry]
Version=1.0
Type=Application
Name=ShieldGuard Firewall Manager
Comment=Manage Linux nftables firewall rules and IP blocklists
Exec=pkexec /usr/bin/python3 /opt/shieldguard/firewall_gui.py
Icon=/opt/shieldguard/shieldguard.png
Terminal=false
Categories=System;Security;Settings;
EOF

chmod 644 "${DESKTOP_FILE}"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
if [[ -d "${REAL_HOME}/Desktop" ]]; then
    cp "${DESKTOP_FILE}" "${REAL_HOME}/Desktop/shieldguard.desktop"
    chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/Desktop/shieldguard.desktop"
    chmod +x "${REAL_HOME}/Desktop/shieldguard.desktop"
fi

echo ""
echo "Installation complete!"
echo "You can now launch 'ShieldGuard Firewall Manager' from your Desktop or Applications Menu."
