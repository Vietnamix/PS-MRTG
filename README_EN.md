# PS-MRTG — MRTG Bandwidth Monitor

> Real-time network bandwidth monitor, **MRTG-style**, written in **PowerShell**.
> Interactive web interface, 100% offline, no installation and no service.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![Chart.js](https://img.shields.io/badge/Chart.js-4.4.0-FF6384?logo=chartdotjs&logoColor=white)
![Mode](https://img.shields.io/badge/ConstrainedLanguage-compatible-success)
![Version](https://img.shields.io/badge/version-1.16-blue)
![License](https://img.shields.io/badge/license-MIT-green)

> 🇫🇷 Une version française de ce document est disponible dans [`README.md`](README.md).

PS-MRTG polls Windows network counters and displays, live in your browser, the
**inbound (IN)** and **outbound (OUT)** throughput of each interface, across 4
time scales (from the last hour to the last 15 days).

---

## ✨ Features

- **Real-time**: automatic refresh every 2 seconds.
- **4 aggregated time views** per interface: Live (1 h), 6 h, 2.5 d, 15 d.
- **"All" view**: the 4 windows side by side in a 2×2 grid, plus a full-screen mode per view.
- **IN / OUT throughput** drawn as smoothed line charts (Chart.js).
- **Automatic Y-axis** with fine 1-2-5 steps (10 / 20 / 50 / 100 / 200 / 500 Mbps … up to 200 Gbps), or a **fixed scale** of your choice.
- **Alarm threshold** (red line), optional, which pushes the scale so it stays visible. Disabled by default.
- **Exact time axis**: partial history only fills its real portion of the chart (1 day of data on the 15-day view = 1/15 of the width), with evenly spaced gridlines (6 segments per chart).
- **Light / dark theme**.
- **Snapshot export** of the Live view.
- **100% offline**: no network dependency once Chart.js is placed locally.
- **ConstrainedLanguage compatible** (locked-down environments) — PowerShell 5.1 and 7+.

---

## 📸 Preview

<p align="center">
  <img src="PS_MRTG_2026_06_02.png" alt="PS_NCDU" width="90%">
</p>

---

## 🧩 The 4 time views

Each view keeps 720 points; the "look-back" is the window covered once the buffer is full.

| View  | Resolution (1 point =) | Look-back calculation                 | Look-back |
|-------|------------------------|---------------------------------------|-----------|
| Live  | 5 s (raw)              | 720 × 5 s = 3,600 s                    | **1 h**   |
| Hour  | 30 s (avg. 6 pts)      | 720 × 30 s = 21,600 s = 360 min       | **6 h**   |
| Day   | 5 min (avg. 60 pts)    | 720 × 5 min = 3,600 min = 60 h        | **2.5 d** |
| Week  | 30 min (avg. 360 pts)  | 720 × 30 min = 21,600 min = 360 h     | **15 d**  |

---

## ✅ Requirements

- **Windows** 10 / 11 or Windows Server.
- **PowerShell 5.1** (built into Windows) or **PowerShell 7+**.
- A modern browser: **Microsoft Edge** or **Google Chrome** recommended.
- **Chart.js 4.4.0** (`chart.umd.min.js`) — see installation below.

> Counters are read via `Get-NetAdapterStatistics` (with fallbacks to other methods). Administrator rights are not required in most cases.

---

## 📥 Installation

1. **Clone the repository** (or download the `.ps1`):

   ```powershell
   git clone https://github.com/your-username/ps-mrtg.git
   cd ps-mrtg
   ```

2. **Provide Chart.js locally** (recommended for offline mode).
   Download `chart.umd.min.js` from the official CDN:

   ```
   https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js
   ```

   Rename it `chartjs.min.js` and place it in one of these locations (the script searches them in this order):

   ```
   %TEMP%\PSMrtg\chartjs.min.js
   %USERPROFILE%\Documents\chartjs.min.js
   %USERPROFILE%\Desktop\chartjs.min.js
   ```

   > If the file is not found, the script attempts to download it automatically, then falls back to the CDN as a last resort (which then requires an Internet connection).

---

## ▶️ Usage

Just run the script:

```powershell
.\PS-MRTG_v1.16.ps1
```

The script:
1. detects active network interfaces;
2. generates the HTML dashboard and the data file in `%TEMP%\PSMrtg\`;
3. automatically opens the browser on the dashboard;
4. updates the data every 2 seconds.

**Stop**: `Ctrl + C` in the PowerShell console.

> **Execution policy** — if the script is blocked, allow it for the current session:
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\PS-MRTG_v1.16.ps1
> ```
> When launched from the ISE, the script relaunches itself in `powershell.exe`.

---

## ⚙️ Configuration

Settings are defined at the top of the script:

| Variable               | Default  | Purpose                                                     |
|------------------------|----------|-------------------------------------------------------------|
| `$IntervalSec`         | `5`      | Counter polling interval (seconds).                         |
| `$WriteEvery`          | `2`      | How often data is written for the browser (seconds).        |
| `$MaxPoints`           | `720`    | Number of points kept per view.                             |
| `$YScaleMode`          | `"auto"` | `"auto"` (stepped) or a fixed value in Mbps (e.g. `1000`).  |
| `$ThresholdAlertMbps`  | `150`    | Pre-filled alarm threshold value (Mbps).                    |
| `$ThresholdEnabled`    | `$false` | Threshold active at startup (`$true` = red line visible).   |

The **Theme**, **Y scale**, **Threshold** and **Point size** settings can also be changed live from the interface.

---

## 🏗️ How it works

```
┌────────────────────┐      writes every 2 s       ┌──────────────────────┐
│  PowerShell         │ ───────────────────────────► │  network_data.js      │
│  (polls every 5 s)  │                              │  (in %TEMP%\PSMrtg)   │
└────────────────────┘                              └───────────┬──────────┘
                                                                │ reloads every 2 s
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │  dashboard.html        │
                                                    │  + Chart.js (offline) │
                                                    └──────────────────────┘
```

- PowerShell reads the network counters every **5 s**, computes throughput, aggregates the 4 views.
- It writes `network_data.js` every **2 s**.
- The browser reloads that file every **2 s** and redraws the charts.

### Generated files (in `%TEMP%\PSMrtg\`)

| File                | Contents                                  |
|---------------------|-------------------------------------------|
| `dashboard.html`    | The dashboard (HTML + JS + Chart.js).     |
| `network_data.js`   | Throughput data, rewritten continuously.  |
| `mrtg_cmd.js`       | Lightweight UI → script command channel.  |
| `chartjs.min.js`    | Local copy of Chart.js (if provided).     |

---

## 🖥️ The dashboard

- **Interface selector**: choose the network adapter to observe.
- **View tabs**: `Live · 1h (5s)`, `6h (30s)`, `2.5j (5min)`, `15j (30min)`, plus the **"Tous"** (All) view.
- **Y scale**: Auto (stepped) or fixed value (10 Mbps → 200 Gbps).
- **Threshold**: tick the box and enter a value in Mbps to show the alarm line.
- **Theme**: light / dark toggle.
- **Snapshot**: exports the Live view.

> Note: the dashboard UI labels are in French (`Tous`, `Echelle Y`, `Seuil`, …), matching the original project.

---

## 🩺 Troubleshooting

- **No interface detected**: check that `Get-NetAdapterStatistics` works (run `Get-NetAdapterStatistics` in a console). Some virtual interfaces do not expose counters.
- **Empty charts / "Chart is not defined"**: `chartjs.min.js` was not found locally and no connection is available. Place the file in `%TEMP%\PSMrtg\`.
- **The browser does not open**: open `%TEMP%\PSMrtg\dashboard.html` manually.
- **Script blocked at launch**: use `-ExecutionPolicy Bypass` (see above).

---

## 🤝 Contributing

Contributions are welcome!

1. Fork the repository.
2. Create a branch: `git checkout -b feature/my-feature`.
3. Commit: `git commit -m "Add my feature"`.
4. Push: `git push origin feature/my-feature`.
5. Open a Pull Request.

Please clearly describe the expected behavior and your test environment (PowerShell version, Windows, browser).

---

## 📝 Changelog (recent excerpts)

- **v1.16** — X axis split into 6 equal segments (10 min in Live, 1 h / 10 h / 60 h depending on the view).
- **v1.15** — Fixed time-domain X axis: data is shown at its real position.
- **v1.14** — Look-back (covered period) shown next to each chart.
- **v1.13 / v1.12** — Dates on the time axis (readability of multi-day views).
- **v1.11** — Time labels at the same size as the throughput labels.
- **v1.10** — Finer scale steps (200 / 500 Mbps…), threshold disabled by default.
- **v1.9** — Shared scale across the 4 views, Y-axis readability, threshold included in the scale.

---

## 📄 License

Distributed under the **MIT** license. See the [`LICENSE`](LICENSE) file.

---

## 👤 Author

**Eric Guiffault**

If this project is useful to you, consider giving it a ⭐ on GitHub!
