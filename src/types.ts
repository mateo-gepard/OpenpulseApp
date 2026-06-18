import type { LucideIcon } from "lucide-react";

export type TabId = "home" | "recovery" | "sleep" | "activity" | "device";

export type ConnectionState =
  | "disconnected"
  | "scanning"
  | "connecting"
  | "connected"
  | "timesync"
  | "streaming"
  | "backfilling"
  | "reconnecting";

export type EnergyMode = "active" | "standby" | "lowPower" | "shipMode";

export type PuckKind = "ppg" | "edaTemp" | "ecg";

export type TrendPoint = {
  label: string;
  value: number;
};

export type Contribution = {
  label: string;
  value: string;
  impact: "up" | "down" | "flat";
};

export type Puck = {
  id: string;
  kind: PuckKind;
  name: string;
  chip: string;
  attached: boolean;
  accent: string;
  metrics: string[];
};

export type NavItem = {
  id: TabId;
  label: string;
  Icon: LucideIcon;
};
