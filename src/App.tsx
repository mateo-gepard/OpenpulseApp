import {
  Activity,
  BatteryCharging,
  Bluetooth,
  Cable,
  Check,
  ChevronRight,
  Database,
  Download,
  HeartPulse,
  Moon,
  PlugZap,
  Power,
  RefreshCcw,
  ShieldCheck,
  SlidersHorizontal,
  Smartphone,
  TimerReset,
  Waves,
  WifiOff,
  Zap,
} from "lucide-react";
import { useMemo, useState, type CSSProperties } from "react";
import {
  activityZones,
  batteryBands,
  gattServices,
  hrvTrend,
  liveMetrics,
  navItems,
  oxygenTrend,
  pucks,
  recoveryContributions,
  recoveryTrend,
  sleepStages,
  strainTrend,
} from "./data/openPulse";
import type { ConnectionState, EnergyMode, Puck, TabId, TrendPoint } from "./types";

type CustomStyle = CSSProperties & Record<string, string | number>;

const connectionFlow: ConnectionState[] = [
  "disconnected",
  "scanning",
  "connecting",
  "connected",
  "timesync",
  "backfilling",
  "streaming",
  "reconnecting",
];

const connectionCopy: Record<ConnectionState, string> = {
  disconnected: "Getrennt",
  scanning: "Scan",
  connecting: "Verbinden",
  connected: "GATT bereit",
  timesync: "Time-Sync",
  streaming: "Live",
  backfilling: "Backfill",
  reconnecting: "Reconnect",
};

const energyModes: Array<{
  id: EnergyMode;
  label: string;
  Icon: typeof Zap;
}> = [
  { id: "active", label: "Aktiv", Icon: Zap },
  { id: "standby", label: "Standby", Icon: Moon },
  { id: "lowPower", label: "Low", Icon: BatteryCharging },
  { id: "shipMode", label: "Ship", Icon: Power },
];

const pageTitles: Record<TabId, string> = {
  home: "Tagesblick",
  recovery: "Recovery",
  sleep: "Schlaf",
  activity: "Aktivität",
  device: "OpenPulse",
};

const today = new Intl.DateTimeFormat("de-DE", {
  weekday: "short",
  day: "2-digit",
  month: "short",
}).format(new Date());

function App() {
  const [activeTab, setActiveTab] = useState<TabId>("home");
  const [connectionState, setConnectionState] = useState<ConnectionState>("streaming");
  const [energyMode, setEnergyMode] = useState<EnergyMode>("active");
  const [knownPucks, setKnownPucks] = useState<Puck[]>(pucks);
  const [sampleRate, setSampleRate] = useState(64);
  const [ledCurrent, setLedCurrent] = useState(14);
  const [localSync, setLocalSync] = useState(false);

  const attachedPucks = useMemo(
    () => knownPucks.filter((puck) => puck.attached),
    [knownPucks],
  );

  const cycleConnection = () => {
    setConnectionState((current) => {
      const nextIndex = (connectionFlow.indexOf(current) + 1) % connectionFlow.length;
      return connectionFlow[nextIndex];
    });
  };

  const togglePuck = (id: string) => {
    setKnownPucks((items) =>
      items.map((puck) =>
        puck.id === id ? { ...puck, attached: !puck.attached } : puck,
      ),
    );
  };

  return (
    <div className="app-root">
      <aside className="nav-rail" aria-label="Hauptnavigation">
        <div className="brand-mark" aria-label="OpenPulse">
          OP
        </div>
        {navItems.map(({ id, label, Icon }) => (
          <button
            key={id}
            className={`rail-button ${activeTab === id ? "active" : ""}`}
            type="button"
            onClick={() => setActiveTab(id)}
            title={label}
            aria-label={label}
            aria-pressed={activeTab === id}
          >
            <Icon size={21} strokeWidth={2.2} />
          </button>
        ))}
      </aside>

      <main className="app-frame">
        <TopBar
          activeTab={activeTab}
          connectionState={connectionState}
          onCycleConnection={cycleConnection}
        />

        <section className="content" aria-label={pageTitles[activeTab]}>
          {activeTab === "home" && (
            <HomePage
              connectionState={connectionState}
              attachedPucks={attachedPucks}
              energyMode={energyMode}
              onOpenDevice={() => setActiveTab("device")}
            />
          )}
          {activeTab === "recovery" && <RecoveryPage />}
          {activeTab === "sleep" && <SleepPage />}
          {activeTab === "activity" && <ActivityPage />}
          {activeTab === "device" && (
            <DevicePage
              connectionState={connectionState}
              energyMode={energyMode}
              onEnergyModeChange={setEnergyMode}
              pucks={knownPucks}
              onTogglePuck={togglePuck}
              sampleRate={sampleRate}
              onSampleRateChange={setSampleRate}
              ledCurrent={ledCurrent}
              onLedCurrentChange={setLedCurrent}
              localSync={localSync}
              onLocalSyncChange={setLocalSync}
              onCycleConnection={cycleConnection}
            />
          )}
        </section>

        <nav className="bottom-nav" aria-label="Hauptnavigation">
          {navItems.map(({ id, label, Icon }) => (
            <button
              key={id}
              className={`bottom-nav-button ${activeTab === id ? "active" : ""}`}
              type="button"
              onClick={() => setActiveTab(id)}
              aria-label={label}
              aria-pressed={activeTab === id}
            >
              <Icon size={20} strokeWidth={2.2} />
              <span>{label}</span>
            </button>
          ))}
        </nav>
      </main>
    </div>
  );
}

function TopBar({
  activeTab,
  connectionState,
  onCycleConnection,
}: {
  activeTab: TabId;
  connectionState: ConnectionState;
  onCycleConnection: () => void;
}) {
  const isLive = connectionState === "streaming";

  return (
    <header className="top-bar">
      <div>
        <p className="eyebrow">{today}</p>
        <h1>{pageTitles[activeTab]}</h1>
      </div>
      <div className="top-actions">
        <button
          className={`icon-status ${isLive ? "online" : ""}`}
          type="button"
          onClick={onCycleConnection}
          title={connectionCopy[connectionState]}
          aria-label={connectionCopy[connectionState]}
        >
          {isLive ? <Bluetooth size={18} /> : <WifiOff size={18} />}
          <span>{connectionCopy[connectionState]}</span>
        </button>
        <button className="icon-button" type="button" title="Akku" aria-label="Akku">
          <BatteryCharging size={19} />
        </button>
      </div>
    </header>
  );
}

function HomePage({
  connectionState,
  attachedPucks,
  energyMode,
  onOpenDevice,
}: {
  connectionState: ConnectionState;
  attachedPucks: Puck[];
  energyMode: EnergyMode;
  onOpenDevice: () => void;
}) {
  return (
    <div className="page-grid home-grid">
      <section className="summary-panel recovery-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Wellness-Readiness</p>
            <h2>Bereit für Belastung</h2>
          </div>
          <button
            className="icon-button subtle"
            type="button"
            title="Aktualisieren"
            aria-label="Aktualisieren"
          >
            <RefreshCcw size={18} />
          </button>
        </div>
        <div className="hero-metrics">
          <RingScore score={86} label="Recovery" tone="green" />
          <div className="metric-stack">
            <MetricLine label="HRV" value="62 ms" delta="+9%" />
            <MetricLine label="RHR" value="48 bpm" delta="-3 bpm" />
            <MetricLine label="Schlaf" value="7 h 54" delta="91%" />
          </div>
        </div>
      </section>

      <section className="summary-panel live-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Live aus Puck 1</p>
            <h2>PPG Stream</h2>
          </div>
          <span className={`dot-state ${connectionState}`}></span>
        </div>
        <div className="live-grid">
          {liveMetrics.map((metric) => (
            <div className="live-tile" key={metric.label}>
              <span>{metric.label}</span>
              <strong>{metric.value}</strong>
              <small>{metric.unit}</small>
            </div>
          ))}
        </div>
        <SparkBars data={strainTrend} tone="#d33e43" compact />
      </section>

      <MetricCard
        title="Strain"
        value="12.4"
        unit="/21"
        Icon={Activity}
        accent="#d33e43"
        footer="TRIMP · 105 Zonenmin."
      />
      <MetricCard
        title="Atem"
        value="13.8"
        unit="/min"
        Icon={Waves}
        accent="#22a699"
        footer="RIIV/RIAV stabil"
      />
      <MetricCard
        title="Akku"
        value="68"
        unit="%"
        Icon={BatteryCharging}
        accent="#f2b84b"
        footer={energyMode === "active" ? "47 h Prognose" : "Standby aktiv"}
      />
      <button className="device-strip" type="button" onClick={onOpenDevice}>
        <DeviceSilhouette pucks={attachedPucks} />
        <span>
          <strong>{attachedPucks.length} Puck aktiv</strong>
          <small>Backfill sauber · QSPI 14 Tage frei</small>
        </span>
        <ChevronRight size={19} />
      </button>
    </div>
  );
}

function RecoveryPage() {
  return (
    <div className="page-grid detail-grid">
      <section className="summary-panel focus-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Baseline 30 Tage</p>
            <h2>Recovery Score</h2>
          </div>
          <RingScore score={86} label="Heute" tone="green" small />
        </div>
        <LineChart data={recoveryTrend} tone="#22a699" />
      </section>

      <section className="summary-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Beitragsfaktoren</p>
            <h2>Rohsignale</h2>
          </div>
          <ShieldCheck size={22} color="#22a699" />
        </div>
        <div className="factor-list">
          {recoveryContributions.map((factor) => (
            <div className={`factor-row ${factor.impact}`} key={factor.label}>
              <span>{factor.label}</span>
              <strong>{factor.value}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Nächtliche RMSSD</p>
            <h2>HRV Trend</h2>
          </div>
          <span className="mono-value">+0.8 z</span>
        </div>
        <SparkBars data={hrvTrend} tone="#7c87ff" />
      </section>
    </div>
  );
}

function SleepPage() {
  return (
    <div className="page-grid detail-grid">
      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">23:18 bis 07:12</p>
            <h2>Hypnogramm</h2>
          </div>
          <Moon size={23} color="#1c1f33" />
        </div>
        <Hypnogram />
      </section>

      <MetricCard
        title="Effizienz"
        value="91"
        unit="%"
        Icon={TimerReset}
        accent="#22a699"
        footer="7 h 54 im Bett"
      />
      <MetricCard
        title="SpO2"
        value="98"
        unit="%"
        Icon={HeartPulse}
        accent="#d33e43"
        footer="Rot/IR Spot-Fenster"
      />

      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Kalibrierung</p>
            <h2>Tag 5 von 7</h2>
          </div>
          <span className="mono-value">71%</span>
        </div>
        <ProgressBar value={71} tone="#d33e43" />
        <SparkBars data={oxygenTrend} tone="#22a699" />
      </section>
    </div>
  );
}

function ActivityPage() {
  return (
    <div className="page-grid detail-grid">
      <section className="summary-panel focus-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Tageslast</p>
            <h2>Strain</h2>
          </div>
          <RingScore score={59} label="12.4" tone="red" small />
        </div>
        <SparkBars data={strainTrend} tone="#d33e43" />
      </section>

      <section className="summary-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">HR-Zonen</p>
            <h2>105 min</h2>
          </div>
          <Activity size={22} color="#d33e43" />
        </div>
        <div className="zone-list">
          {activityZones.map((zone) => (
            <div className="zone-row" key={zone.label}>
              <span>{zone.label}</span>
              <div className="zone-track">
                <i
                  style={
                    {
                      "--zone-width": `${(zone.minutes / 42) * 100}%`,
                      "--zone-color": zone.color,
                    } as CustomStyle
                  }
                ></i>
              </div>
              <strong>{zone.minutes}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Sessions</p>
            <h2>Heute</h2>
          </div>
          <button className="icon-button subtle" type="button" title="Export" aria-label="Export">
            <Download size={18} />
          </button>
        </div>
        <div className="session-list">
          <SessionRow title="Morgenlauf" meta="38 min · Zone 2" score="7.1" />
          <SessionRow title="Pendeln" meta="22 min · leicht" score="2.4" />
          <SessionRow title="Krafttraining" meta="45 min · gemischt" score="5.8" />
        </div>
      </section>
    </div>
  );
}

function DevicePage({
  connectionState,
  energyMode,
  onEnergyModeChange,
  pucks,
  onTogglePuck,
  sampleRate,
  onSampleRateChange,
  ledCurrent,
  onLedCurrentChange,
  localSync,
  onLocalSyncChange,
  onCycleConnection,
}: {
  connectionState: ConnectionState;
  energyMode: EnergyMode;
  onEnergyModeChange: (mode: EnergyMode) => void;
  pucks: Puck[];
  onTogglePuck: (id: string) => void;
  sampleRate: number;
  onSampleRateChange: (value: number) => void;
  ledCurrent: number;
  onLedCurrentChange: (value: number) => void;
  localSync: boolean;
  onLocalSyncChange: (value: boolean) => void;
  onCycleConnection: () => void;
}) {
  return (
    <div className="page-grid device-grid">
      <section className="summary-panel device-overview">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">XIAO nRF52840 Sense</p>
            <h2>{connectionCopy[connectionState]}</h2>
          </div>
          <button
            className="icon-button brand"
            type="button"
            onClick={onCycleConnection}
            title="BLE"
            aria-label="BLE"
          >
            <Bluetooth size={18} />
          </button>
        </div>
        <DeviceSilhouette pucks={pucks.filter((puck) => puck.attached)} large />
        <div className="status-grid">
          <MetricLine label="Akku" value="68%" delta="47 h" />
          <MetricLine label="QSPI" value="82%" delta="frei" />
          <MetricLine label="MTU" value="247" delta="2M PHY" />
        </div>
      </section>

      <section className="summary-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Energie</p>
            <h2>Modus</h2>
          </div>
          <Power size={22} color="#1c1f33" />
        </div>
        <SegmentedModes value={energyMode} onChange={onEnergyModeChange} />
        <div className="battery-bands">
          {batteryBands.map((band) => (
            <div key={band.label}>
              <i style={{ backgroundColor: band.tone }}></i>
              <span>{band.label}</span>
              <strong>{band.value}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Puck-Erkennung</p>
            <h2>Module</h2>
          </div>
          <PlugZap size={22} color="#d33e43" />
        </div>
        <div className="puck-grid">
          {pucks.map((puck) => (
            <PuckCard key={puck.id} puck={puck} onToggle={() => onTogglePuck(puck.id)} />
          ))}
        </div>
      </section>

      <section className="summary-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Control</p>
            <h2>Sampling</h2>
          </div>
          <SlidersHorizontal size={22} color="#1c1f33" />
        </div>
        <SliderControl
          label="PPG"
          value={sampleRate}
          min={25}
          max={128}
          unit="Hz"
          onChange={onSampleRateChange}
        />
        <SliderControl
          label="LED"
          value={ledCurrent}
          min={4}
          max={24}
          unit="mA"
          onChange={onLedCurrentChange}
        />
      </section>

      <section className="summary-panel">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">GATT</p>
            <h2>Services</h2>
          </div>
          <Cable size={22} color="#7c87ff" />
        </div>
        <div className="service-list">
          {gattServices.map((service) => (
            <div key={service.label}>
              <span>{service.label}</span>
              <strong>{service.value}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="summary-panel span-two">
        <div className="panel-heading">
          <div>
            <p className="eyebrow">Datenhoheit</p>
            <h2>Lokal-first</h2>
          </div>
          <Database size={22} color="#22a699" />
        </div>
        <div className="data-actions">
          <button className="action-button" type="button">
            <Download size={18} />
            <span>CSV</span>
          </button>
          <button className="action-button" type="button">
            <Smartphone size={18} />
            <span>Backfill</span>
          </button>
          <label className="toggle-row">
            <input
              type="checkbox"
              checked={localSync}
              onChange={(event) => onLocalSyncChange(event.target.checked)}
            />
            <span>MQTT Sync</span>
          </label>
        </div>
      </section>
    </div>
  );
}

function MetricCard({
  title,
  value,
  unit,
  Icon,
  accent,
  footer,
}: {
  title: string;
  value: string;
  unit: string;
  Icon: typeof Activity;
  accent: string;
  footer: string;
}) {
  return (
    <section className="summary-panel metric-card" style={{ "--accent": accent } as CustomStyle}>
      <div className="metric-icon">
        <Icon size={20} />
      </div>
      <span>{title}</span>
      <strong>
        {value}
        <small>{unit}</small>
      </strong>
      <em>{footer}</em>
    </section>
  );
}

function RingScore({
  score,
  label,
  tone,
  small = false,
}: {
  score: number;
  label: string;
  tone: "green" | "red";
  small?: boolean;
}) {
  return (
    <div
      className={`ring-score ${tone} ${small ? "small" : ""}`}
      style={{ "--score": `${score * 3.6}deg` } as CustomStyle}
      aria-label={`${label} ${score}`}
    >
      <div>
        <strong>{label === "12.4" ? label : score}</strong>
        <span>{label}</span>
      </div>
    </div>
  );
}

function MetricLine({
  label,
  value,
  delta,
}: {
  label: string;
  value: string;
  delta: string;
}) {
  return (
    <div className="metric-line">
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{delta}</small>
    </div>
  );
}

function SparkBars({
  data,
  tone,
  compact = false,
}: {
  data: TrendPoint[];
  tone: string;
  compact?: boolean;
}) {
  const max = Math.max(...data.map((point) => point.value));

  return (
    <div className={`spark-bars ${compact ? "compact" : ""}`} aria-label="Trend">
      {data.map((point) => (
        <div className="spark-column" key={point.label}>
          <i
            style={
              {
                "--bar-height": `${Math.max(12, (point.value / max) * 100)}%`,
                "--bar-color": tone,
              } as CustomStyle
            }
          ></i>
          {!compact && <span>{point.label}</span>}
        </div>
      ))}
    </div>
  );
}

function LineChart({ data, tone }: { data: TrendPoint[]; tone: string }) {
  const max = Math.max(...data.map((point) => point.value));
  const min = Math.min(...data.map((point) => point.value));
  const range = Math.max(1, max - min);
  const points = data
    .map((point, index) => {
      const x = (index / (data.length - 1)) * 100;
      const y = 82 - ((point.value - min) / range) * 58;
      return `${x},${y}`;
    })
    .join(" ");

  return (
    <div className="line-chart">
      <svg viewBox="0 0 100 100" role="img" aria-label="Recovery Trend">
        <polyline points={points} fill="none" stroke={tone} strokeWidth="4" />
        {data.map((point, index) => {
          const x = (index / (data.length - 1)) * 100;
          const y = 82 - ((point.value - min) / range) * 58;
          return <circle key={point.label} cx={x} cy={y} r="3.5" fill={tone} />;
        })}
      </svg>
      <div className="chart-labels">
        {data.map((point) => (
          <span key={point.label}>{point.label}</span>
        ))}
      </div>
    </div>
  );
}

function Hypnogram() {
  return (
    <div className="hypnogram">
      <div className="stage-grid">
        {["Wach", "REM", "Leicht", "Tief"].map((stage) => (
          <span key={stage}>{stage}</span>
        ))}
      </div>
      <div className="stage-track">
        {sleepStages.map((stage, index) => (
          <i
            key={`${stage.label}-${index}`}
            title={stage.label}
            style={
              {
                "--stage-left": `${stage.start}%`,
                "--stage-width": `${stage.width}%`,
                "--stage-top": `${stage.lane * 25}%`,
                "--stage-color": stage.color,
              } as CustomStyle
            }
          ></i>
        ))}
      </div>
      <div className="time-axis">
        <span>23:18</span>
        <span>03:15</span>
        <span>07:12</span>
      </div>
    </div>
  );
}

function ProgressBar({ value, tone }: { value: number; tone: string }) {
  return (
    <div className="progress-bar" aria-label={`${value}%`}>
      <i
        style={
          {
            "--progress": `${value}%`,
            "--progress-tone": tone,
          } as CustomStyle
        }
      ></i>
    </div>
  );
}

function SegmentedModes({
  value,
  onChange,
}: {
  value: EnergyMode;
  onChange: (value: EnergyMode) => void;
}) {
  return (
    <div className="segmented-control">
      {energyModes.map(({ id, label, Icon }) => (
        <button
          key={id}
          type="button"
          className={value === id ? "active" : ""}
          onClick={() => onChange(id)}
          aria-pressed={value === id}
          title={label}
        >
          <Icon size={17} />
          <span>{label}</span>
        </button>
      ))}
    </div>
  );
}

function PuckCard({ puck, onToggle }: { puck: Puck; onToggle: () => void }) {
  return (
    <div className={`puck-card ${puck.attached ? "attached" : ""}`}>
      <div className="puck-top">
        <span style={{ "--puck-accent": puck.accent } as CustomStyle}></span>
        <button
          className="icon-button subtle"
          type="button"
          onClick={onToggle}
          title={puck.attached ? "Entfernen" : "Stecken"}
          aria-label={puck.attached ? "Entfernen" : "Stecken"}
        >
          {puck.attached ? <Check size={17} /> : <PlugZap size={17} />}
        </button>
      </div>
      <strong>{puck.name}</strong>
      <small>{puck.chip}</small>
      <div className="metric-tags">
        {puck.metrics.map((metric) => (
          <em key={metric}>{metric}</em>
        ))}
      </div>
    </div>
  );
}

function SliderControl({
  label,
  value,
  min,
  max,
  unit,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  unit: string;
  onChange: (value: number) => void;
}) {
  return (
    <label className="slider-control">
      <span>
        {label}
        <strong>
          {value} {unit}
        </strong>
      </span>
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </label>
  );
}

function DeviceSilhouette({ pucks, large = false }: { pucks: Puck[]; large?: boolean }) {
  return (
    <div className={`device-visual ${large ? "large" : ""}`} aria-hidden="true">
      <div className="band top"></div>
      <div className="core">
        <span className="sensor-dot"></span>
        {pucks.slice(0, 2).map((puck, index) => (
          <i
            key={puck.id}
            style={
              {
                "--puck-accent": puck.accent,
                "--puck-offset": `${index * 18}px`,
              } as CustomStyle
            }
          ></i>
        ))}
      </div>
      <div className="band bottom"></div>
    </div>
  );
}

function SessionRow({
  title,
  meta,
  score,
}: {
  title: string;
  meta: string;
  score: string;
}) {
  return (
    <div className="session-row">
      <div>
        <strong>{title}</strong>
        <span>{meta}</span>
      </div>
      <em>{score}</em>
    </div>
  );
}

export default App;
