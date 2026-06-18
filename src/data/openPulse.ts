import {
  Activity,
  BatteryMedium,
  BedDouble,
  Gauge,
  HeartPulse,
  Watch,
} from "lucide-react";
import type { Contribution, NavItem, Puck, TrendPoint } from "../types";

export const navItems: NavItem[] = [
  { id: "home", label: "Home", Icon: Gauge },
  { id: "recovery", label: "Recovery", Icon: HeartPulse },
  { id: "sleep", label: "Schlaf", Icon: BedDouble },
  { id: "activity", label: "Aktivität", Icon: Activity },
  { id: "device", label: "Gerät", Icon: Watch },
];

export const recoveryTrend: TrendPoint[] = [
  { label: "Fr", value: 61 },
  { label: "Sa", value: 72 },
  { label: "So", value: 68 },
  { label: "Mo", value: 75 },
  { label: "Di", value: 82 },
  { label: "Mi", value: 79 },
  { label: "Heute", value: 86 },
];

export const hrvTrend: TrendPoint[] = [
  { label: "Fr", value: 48 },
  { label: "Sa", value: 52 },
  { label: "So", value: 51 },
  { label: "Mo", value: 55 },
  { label: "Di", value: 58 },
  { label: "Mi", value: 56 },
  { label: "Heute", value: 62 },
];

export const strainTrend: TrendPoint[] = [
  { label: "06", value: 18 },
  { label: "09", value: 28 },
  { label: "12", value: 44 },
  { label: "15", value: 64 },
  { label: "18", value: 72 },
  { label: "21", value: 76 },
];

export const oxygenTrend: TrendPoint[] = [
  { label: "00", value: 97 },
  { label: "01", value: 98 },
  { label: "02", value: 97 },
  { label: "03", value: 96 },
  { label: "04", value: 98 },
  { label: "05", value: 97 },
  { label: "06", value: 98 },
];

export const sleepStages = [
  { label: "Wach", start: 0, width: 7, lane: 0, color: "#d33e43" },
  { label: "Leicht", start: 7, width: 19, lane: 1, color: "#7c87ff" },
  { label: "Tief", start: 26, width: 14, lane: 3, color: "#1c1f33" },
  { label: "REM", start: 40, width: 13, lane: 2, color: "#22a699" },
  { label: "Leicht", start: 53, width: 18, lane: 1, color: "#7c87ff" },
  { label: "Tief", start: 71, width: 11, lane: 3, color: "#1c1f33" },
  { label: "REM", start: 82, width: 12, lane: 2, color: "#22a699" },
  { label: "Wach", start: 94, width: 6, lane: 0, color: "#d33e43" },
];

export const recoveryContributions: Contribution[] = [
  { label: "RMSSD", value: "62 ms", impact: "up" },
  { label: "Ruhepuls", value: "48 bpm", impact: "up" },
  { label: "Schlafqualität", value: "91%", impact: "up" },
  { label: "Baseline", value: "+0.8 z", impact: "flat" },
];

export const activityZones = [
  { label: "Zone 1", minutes: 42, color: "#22a699" },
  { label: "Zone 2", minutes: 36, color: "#84cc16" },
  { label: "Zone 3", minutes: 18, color: "#f2b84b" },
  { label: "Zone 4", minutes: 7, color: "#f97316" },
  { label: "Zone 5", minutes: 2, color: "#d33e43" },
];

export const pucks: Puck[] = [
  {
    id: "puck-1",
    kind: "ppg",
    name: "Puck 1",
    chip: "MAXM86161 · I2C 0x62",
    attached: true,
    accent: "#d33e43",
    metrics: ["HR", "HRV", "SpO2", "Atem", "Schlaf"],
  },
  {
    id: "puck-2",
    kind: "edaTemp",
    name: "Puck 2",
    chip: "TMP117 + EDA",
    attached: false,
    accent: "#22a699",
    metrics: ["EDA", "Temperatur", "Stress"],
  },
  {
    id: "puck-ecg",
    kind: "ecg",
    name: "ECG",
    chip: "V2 Gehäusekontakt",
    attached: false,
    accent: "#7c87ff",
    metrics: ["Spot-ECG"],
  },
];

export const batteryBands = [
  { label: "> 20%", value: "Normal", tone: "#22a699" },
  { label: "10%", value: "LowPower", tone: "#f2b84b" },
  { label: "5%", value: "HR-only", tone: "#f97316" },
  { label: "3%", value: "SafeShutdown", tone: "#d33e43" },
];

export const gattServices = [
  { label: "Device Info", value: "0x180A" },
  { label: "Battery", value: "0x180F" },
  { label: "Control", value: "Custom" },
  { label: "Live Stream", value: "Notify" },
  { label: "Bulk", value: "Indicate" },
];

export const liveMetrics = [
  { label: "HR", value: "64", unit: "bpm" },
  { label: "IBI", value: "938", unit: "ms" },
  { label: "SpO2", value: "98", unit: "%" },
  { label: "Atem", value: "13.8", unit: "/min" },
];

export { BatteryMedium };
