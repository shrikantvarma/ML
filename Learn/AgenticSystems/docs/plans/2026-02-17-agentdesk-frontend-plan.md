# AgentDesk Frontend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the AgentDesk frontend — a warm, human-centered AI support dashboard with a focused review flow, agent trace visualization, and ticket management.

**Architecture:** Next.js 14 App Router with shadcn/ui (Radix-based) components, Tailwind CSS for styling, TanStack Query for API state management with polling, and Framer Motion for smooth transitions in the review flow. The frontend lives in `frontend/` within the AgentDesk project and consumes the existing FastAPI backend at `http://localhost:8000`.

**Tech Stack:** Next.js 14, TypeScript, Tailwind CSS, shadcn/ui, TanStack Query, Framer Motion

---

## Project Structure

```
frontend/
├── app/
│   ├── layout.tsx              # Root layout with QueryClientProvider
│   ├── page.tsx                # Dashboard (home)
│   ├── tickets/
│   │   └── [id]/
│   │       └── page.tsx        # Ticket detail
│   ├── review/
│   │   └── page.tsx            # Focused review flow
│   └── submit/
│       └── page.tsx            # Submit ticket form
├── components/
│   ├── ui/                     # shadcn/ui primitives (auto-generated)
│   ├── layout/
│   │   └── app-shell.tsx       # Top nav + main content wrapper
│   ├── dashboard/
│   │   ├── attention-zone.tsx  # Escalated tickets section
│   │   ├── activity-feed.tsx   # Recent AI activity
│   │   └── ticket-table.tsx    # Full ticket list with filters
│   ├── ticket/
│   │   ├── status-badge.tsx    # Status pill (resolved, awaiting, etc.)
│   │   ├── urgency-indicator.tsx
│   │   ├── category-badge.tsx
│   │   └── ticket-info.tsx     # Shared ticket display component
│   ├── review/
│   │   ├── review-card.tsx     # Single review ticket (full context)
│   │   └── modify-editor.tsx   # Pre-filled response editor
│   └── trace/
│       ├── trace-timeline.tsx  # Vertical timeline of agent steps
│       └── trace-step.tsx      # Single expandable agent step
├── lib/
│   ├── api.ts                  # Fetch wrapper for all endpoints
│   ├── hooks.ts                # TanStack Query hooks
│   ├── types.ts                # TypeScript types matching backend
│   └── utils.ts                # Formatting (dates, currency, relative time)
├── __tests__/
│   ├── lib/
│   │   ├── api.test.ts
│   │   └── utils.test.ts
│   └── components/
│       └── review-card.test.tsx
├── next.config.js
├── tailwind.config.ts
├── tsconfig.json
└── package.json
```

---

## Task 1: Scaffold Next.js Project

**Files:**
- Create: `frontend/` (entire scaffold)

**Step 1: Create Next.js app**

```bash
cd /path/to/AgenticSystems
npx create-next-app@latest frontend --typescript --tailwind --eslint --app --src-dir=false --import-alias="@/*" --use-npm
```

When prompted, accept defaults. This creates the full Next.js scaffold with App Router and Tailwind.

**Step 2: Install dependencies**

```bash
cd frontend
npm install @tanstack/react-query framer-motion
npm install -D @testing-library/react @testing-library/jest-dom @testing-library/user-event jest jest-environment-jsdom @types/jest ts-jest
```

**Step 3: Initialize shadcn/ui**

```bash
npx shadcn@latest init
```

Choose: New York style, Zinc base color, CSS variables: yes.

**Step 4: Add shadcn components we'll need**

```bash
npx shadcn@latest add button badge card dialog textarea select tabs separator scroll-area
```

**Step 5: Configure API proxy**

Edit `frontend/next.config.js` to proxy API calls to the backend:

```js
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8000/:path*",
      },
    ];
  },
};

module.exports = nextConfig;
```

**Step 6: Verify it runs**

```bash
npm run dev
```

Visit `http://localhost:3000` — should see the Next.js default page.

**Step 7: Commit**

```bash
git add frontend/
git commit -m "feat: scaffold Next.js frontend with shadcn/ui, TanStack Query, Framer Motion"
```

---

## Task 2: TypeScript Types & API Client

**Files:**
- Create: `frontend/lib/types.ts`
- Create: `frontend/lib/api.ts`
- Create: `frontend/lib/utils.ts`
- Test: `frontend/__tests__/lib/utils.test.ts`

**Step 1: Write types**

Create `frontend/lib/types.ts`:

```typescript
// Ticket status
export type TicketStatus = "processing" | "resolved" | "awaiting_human_review" | "escalated";

// Ticket category
export type TicketCategory = "order_issue" | "return_request" | "product_question" | "billing" | "complaint";

// Urgency level
export type TicketUrgency = "low" | "medium" | "high" | "critical";

// Resolution action
export type ResolutionAction = "refund" | "replacement" | "escalate" | "info_only" | "cancel_order";

// Review action
export type ReviewAction = "approve" | "modify" | "reject";

// API response: single ticket
export interface Ticket {
  ticket_id: string;
  status: TicketStatus;
  category: TicketCategory | null;
  urgency: TicketUrgency | null;
  resolution_action: ResolutionAction | null;
  customer_response: string | null;
  internal_notes: string | null;
}

// API response: ticket list
export interface TicketListResponse {
  tickets: Ticket[];
}

// API response: trace
export interface TraceEntry {
  agent: string;
  timestamp: string;
  input_summary: string;
  output_summary: string;
  confidence: number | null;
}

export interface TraceResponse {
  ticket_id: string;
  trace_log: TraceEntry[];
}

// API request: create ticket
export interface CreateTicketRequest {
  customer_id: string;
  message: string;
}

// API request: review ticket
export interface ReviewTicketRequest {
  action: ReviewAction;
  modified_response?: string;
}

// API response: review result
export interface ReviewResponse {
  ticket_id: string;
  status: TicketStatus;
}

// Seed customers (for the submit form dropdown)
export const CUSTOMERS = [
  { id: "C001", name: "Alice Johnson", tier: "Premium" },
  { id: "C002", name: "Bob Smith", tier: "Standard" },
  { id: "C003", name: "Carol Williams", tier: "VIP" },
  { id: "C004", name: "Dave Brown", tier: "Standard" },
] as const;
```

**Step 2: Write API client**

Create `frontend/lib/api.ts`:

```typescript
import type {
  Ticket,
  TicketListResponse,
  TraceResponse,
  CreateTicketRequest,
  ReviewTicketRequest,
  ReviewResponse,
  TicketStatus,
  TicketCategory,
} from "./types";

const BASE_URL = "/api";

async function fetchJSON<T>(url: string, options?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    throw new Error(`API error: ${res.status} ${res.statusText}`);
  }
  return res.json();
}

export async function getTickets(filters?: {
  status?: TicketStatus;
  category?: TicketCategory;
}): Promise<Ticket[]> {
  const params = new URLSearchParams();
  if (filters?.status) params.set("status", filters.status);
  if (filters?.category) params.set("category", filters.category);
  const query = params.toString();
  const url = `${BASE_URL}/tickets${query ? `?${query}` : ""}`;
  const data = await fetchJSON<TicketListResponse>(url);
  return data.tickets;
}

export async function getTicket(ticketId: string): Promise<Ticket> {
  return fetchJSON<Ticket>(`${BASE_URL}/tickets/${ticketId}`);
}

export async function getTicketTrace(ticketId: string): Promise<TraceResponse> {
  return fetchJSON<TraceResponse>(`${BASE_URL}/tickets/${ticketId}/trace`);
}

export async function createTicket(req: CreateTicketRequest): Promise<Ticket> {
  return fetchJSON<Ticket>(`${BASE_URL}/tickets`, {
    method: "POST",
    body: JSON.stringify(req),
  });
}

export async function reviewTicket(
  ticketId: string,
  req: ReviewTicketRequest
): Promise<ReviewResponse> {
  return fetchJSON<ReviewResponse>(`${BASE_URL}/tickets/${ticketId}/review`, {
    method: "POST",
    body: JSON.stringify(req),
  });
}
```

**Step 3: Write utility functions**

Create `frontend/lib/utils.ts` (extend the shadcn `cn` util that already exists):

```typescript
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(amount);
}

export function formatRelativeTime(timestamp: string): string {
  const now = new Date();
  const then = new Date(timestamp);
  const diffMs = now.getTime() - then.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  const diffMin = Math.floor(diffSec / 60);
  const diffHr = Math.floor(diffMin / 60);
  const diffDays = Math.floor(diffHr / 24);

  if (diffSec < 60) return "just now";
  if (diffMin < 60) return `${diffMin}m ago`;
  if (diffHr < 24) return `${diffHr}h ago`;
  return `${diffDays}d ago`;
}

export function formatTraceTimeDelta(currentTs: string, firstTs: string): string {
  const diff = new Date(currentTs).getTime() - new Date(firstTs).getTime();
  return `+${(diff / 1000).toFixed(1)}s`;
}

export function statusLabel(status: string): string {
  const labels: Record<string, string> = {
    processing: "Processing",
    resolved: "Resolved",
    awaiting_human_review: "Needs Review",
    escalated: "Escalated",
  };
  return labels[status] ?? status;
}

export function categoryLabel(category: string): string {
  const labels: Record<string, string> = {
    order_issue: "Order Issue",
    return_request: "Return Request",
    product_question: "Product Question",
    billing: "Billing",
    complaint: "Complaint",
  };
  return labels[category] ?? category;
}

export function urgencyLabel(urgency: string): string {
  const labels: Record<string, string> = {
    low: "Low",
    medium: "Medium",
    high: "High",
    critical: "Critical",
  };
  return labels[urgency] ?? urgency;
}
```

**Step 4: Write utility tests**

Create `frontend/__tests__/lib/utils.test.ts`:

```typescript
import { formatRelativeTime, formatTraceTimeDelta, statusLabel, categoryLabel } from "@/lib/utils";

describe("formatRelativeTime", () => {
  it("returns 'just now' for recent timestamps", () => {
    const now = new Date().toISOString();
    expect(formatRelativeTime(now)).toBe("just now");
  });

  it("returns minutes for timestamps within an hour", () => {
    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000).toISOString();
    expect(formatRelativeTime(fiveMinAgo)).toBe("5m ago");
  });
});

describe("formatTraceTimeDelta", () => {
  it("calculates delta from first timestamp", () => {
    const first = "2026-02-17T10:30:00Z";
    const current = "2026-02-17T10:30:01.200Z";
    expect(formatTraceTimeDelta(current, first)).toBe("+1.2s");
  });
});

describe("statusLabel", () => {
  it("maps awaiting_human_review to Needs Review", () => {
    expect(statusLabel("awaiting_human_review")).toBe("Needs Review");
  });
});

describe("categoryLabel", () => {
  it("maps return_request to Return Request", () => {
    expect(categoryLabel("return_request")).toBe("Return Request");
  });
});
```

**Step 5: Run tests**

```bash
npm test -- --passWithNoTests
```

**Step 6: Commit**

```bash
git add frontend/lib/ frontend/__tests__/
git commit -m "feat: add TypeScript types, API client, and utility functions"
```

---

## Task 3: TanStack Query Hooks & App Layout

**Files:**
- Create: `frontend/lib/hooks.ts`
- Create: `frontend/components/providers.tsx`
- Modify: `frontend/app/layout.tsx`
- Create: `frontend/components/layout/app-shell.tsx`

**Step 1: Create TanStack Query hooks**

Create `frontend/lib/hooks.ts`:

```typescript
"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import * as api from "./api";
import type {
  TicketStatus,
  TicketCategory,
  CreateTicketRequest,
  ReviewTicketRequest,
} from "./types";

export function useTickets(filters?: { status?: TicketStatus; category?: TicketCategory }) {
  return useQuery({
    queryKey: ["tickets", filters],
    queryFn: () => api.getTickets(filters),
    refetchInterval: 5000, // Poll every 5s
  });
}

export function useTicket(ticketId: string) {
  return useQuery({
    queryKey: ["ticket", ticketId],
    queryFn: () => api.getTicket(ticketId),
    enabled: !!ticketId,
  });
}

export function useTicketTrace(ticketId: string) {
  return useQuery({
    queryKey: ["trace", ticketId],
    queryFn: () => api.getTicketTrace(ticketId),
    enabled: !!ticketId,
  });
}

export function useEscalatedTickets() {
  return useTickets({ status: "awaiting_human_review" });
}

export function useCreateTicket() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (req: CreateTicketRequest) => api.createTicket(req),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tickets"] });
    },
  });
}

export function useReviewTicket() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ ticketId, req }: { ticketId: string; req: ReviewTicketRequest }) =>
      api.reviewTicket(ticketId, req),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["tickets"] });
    },
  });
}
```

**Step 2: Create providers wrapper**

Create `frontend/components/providers.tsx`:

```typescript
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 2000,
        retry: 1,
      },
    },
  }));

  return (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  );
}
```

**Step 3: Create app shell**

Create `frontend/components/layout/app-shell.tsx`:

```tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useEscalatedTickets } from "@/lib/hooks";

const NAV_ITEMS = [
  { href: "/", label: "Dashboard" },
  { href: "/review", label: "Review" },
  { href: "/submit", label: "Submit Ticket" },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { data: escalated } = useEscalatedTickets();
  const escalatedCount = escalated?.length ?? 0;

  return (
    <div className="min-h-screen bg-stone-50">
      {/* Top navigation */}
      <header className="sticky top-0 z-50 border-b border-stone-200 bg-white/80 backdrop-blur-sm">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="text-lg font-semibold text-stone-900 tracking-tight">
            AgentDesk
          </Link>
          <nav className="flex items-center gap-1">
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "relative rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
                  pathname === item.href
                    ? "bg-stone-100 text-stone-900"
                    : "text-stone-500 hover:text-stone-700 hover:bg-stone-50"
                )}
              >
                {item.label}
                {item.label === "Review" && escalatedCount > 0 && (
                  <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-amber-500 px-1 text-[10px] font-bold text-white">
                    {escalatedCount}
                  </span>
                )}
              </Link>
            ))}
          </nav>
        </div>
      </header>

      {/* Main content */}
      <main className="mx-auto max-w-6xl px-6 py-8">
        {children}
      </main>
    </div>
  );
}
```

**Step 4: Update root layout**

Replace `frontend/app/layout.tsx`:

```tsx
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/providers";
import { AppShell } from "@/components/layout/app-shell";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "AgentDesk",
  description: "AI-powered customer support dashboard",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={inter.className}>
        <Providers>
          <AppShell>{children}</AppShell>
        </Providers>
      </body>
    </html>
  );
}
```

**Step 5: Verify it compiles**

```bash
npm run build
```

**Step 6: Commit**

```bash
git add frontend/lib/hooks.ts frontend/components/ frontend/app/layout.tsx
git commit -m "feat: add TanStack Query hooks, providers, and app shell layout"
```

---

## Task 4: Badge Components (Status, Urgency, Category)

**Files:**
- Create: `frontend/components/ticket/status-badge.tsx`
- Create: `frontend/components/ticket/urgency-indicator.tsx`
- Create: `frontend/components/ticket/category-badge.tsx`

**Step 1: Status badge**

Create `frontend/components/ticket/status-badge.tsx`:

```tsx
import { Badge } from "@/components/ui/badge";
import { cn, statusLabel } from "@/lib/utils";
import type { TicketStatus } from "@/lib/types";

const STATUS_STYLES: Record<TicketStatus, string> = {
  processing: "bg-blue-50 text-blue-700 border-blue-200",
  resolved: "bg-emerald-50 text-emerald-700 border-emerald-200",
  awaiting_human_review: "bg-amber-50 text-amber-700 border-amber-200",
  escalated: "bg-rose-50 text-rose-700 border-rose-200",
};

const STATUS_ICONS: Record<TicketStatus, string> = {
  processing: "⏳",
  resolved: "✓",
  awaiting_human_review: "●",
  escalated: "⚠",
};

export function StatusBadge({ status }: { status: TicketStatus }) {
  return (
    <Badge variant="outline" className={cn("gap-1 font-medium", STATUS_STYLES[status])}>
      <span aria-hidden>{STATUS_ICONS[status]}</span>
      {statusLabel(status)}
    </Badge>
  );
}
```

**Step 2: Urgency indicator**

Create `frontend/components/ticket/urgency-indicator.tsx`:

```tsx
import { cn, urgencyLabel } from "@/lib/utils";
import type { TicketUrgency } from "@/lib/types";

const URGENCY_STYLES: Record<TicketUrgency, string> = {
  low: "bg-stone-300",
  medium: "bg-amber-400",
  high: "bg-orange-500",
  critical: "bg-red-500 animate-pulse",
};

export function UrgencyIndicator({ urgency }: { urgency: TicketUrgency }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-stone-600">
      <span
        className={cn("h-2 w-2 rounded-full", URGENCY_STYLES[urgency])}
        aria-label={`Urgency: ${urgencyLabel(urgency)}`}
      />
      {urgencyLabel(urgency)}
    </span>
  );
}
```

**Step 3: Category badge**

Create `frontend/components/ticket/category-badge.tsx`:

```tsx
import { Badge } from "@/components/ui/badge";
import { categoryLabel } from "@/lib/utils";
import type { TicketCategory } from "@/lib/types";

export function CategoryBadge({ category }: { category: TicketCategory }) {
  return (
    <Badge variant="secondary" className="font-normal text-stone-600 bg-stone-100">
      {categoryLabel(category)}
    </Badge>
  );
}
```

**Step 4: Commit**

```bash
git add frontend/components/ticket/
git commit -m "feat: add status, urgency, and category badge components"
```

---

## Task 5: Dashboard Page

**Files:**
- Create: `frontend/components/dashboard/attention-zone.tsx`
- Create: `frontend/components/dashboard/activity-feed.tsx`
- Create: `frontend/components/dashboard/ticket-table.tsx`
- Modify: `frontend/app/page.tsx`

**Step 1: Attention zone (escalated tickets)**

Create `frontend/components/dashboard/attention-zone.tsx`:

```tsx
"use client";

import Link from "next/link";
import { useEscalatedTickets } from "@/lib/hooks";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { UrgencyIndicator } from "@/components/ticket/urgency-indicator";
import { CategoryBadge } from "@/components/ticket/category-badge";

export function AttentionZone() {
  const { data: tickets, isLoading } = useEscalatedTickets();

  if (isLoading) {
    return (
      <div className="rounded-2xl border border-amber-200 bg-amber-50/50 p-6">
        <p className="text-sm text-stone-500">Loading...</p>
      </div>
    );
  }

  if (!tickets || tickets.length === 0) {
    return (
      <div className="rounded-2xl border border-emerald-200 bg-emerald-50/50 p-6 text-center">
        <p className="text-lg font-medium text-emerald-800">All caught up</p>
        <p className="text-sm text-emerald-600 mt-1">No tickets need your review right now.</p>
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-amber-200 bg-amber-50/30 p-6">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-lg font-semibold text-stone-900">
            {tickets.length} {tickets.length === 1 ? "ticket needs" : "tickets need"} your review
          </h2>
          <p className="text-sm text-stone-500 mt-0.5">
            The AI couldn&apos;t confidently resolve these
          </p>
        </div>
        <Link href="/review">
          <Button className="bg-amber-600 hover:bg-amber-700 text-white rounded-xl">
            Start Review
          </Button>
        </Link>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {tickets.map((ticket) => (
          <Link key={ticket.ticket_id} href={`/tickets/${ticket.ticket_id}`}>
            <Card className="p-4 hover:shadow-md transition-shadow cursor-pointer border-amber-100">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-mono text-stone-400">{ticket.ticket_id}</span>
                {ticket.urgency && <UrgencyIndicator urgency={ticket.urgency} />}
              </div>
              {ticket.category && <CategoryBadge category={ticket.category} />}
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
```

**Step 2: Activity feed**

Create `frontend/components/dashboard/activity-feed.tsx`:

```tsx
"use client";

import Link from "next/link";
import { useTickets } from "@/lib/hooks";
import { StatusBadge } from "@/components/ticket/status-badge";
import { CategoryBadge } from "@/components/ticket/category-badge";

export function ActivityFeed() {
  const { data: tickets, isLoading } = useTickets();

  if (isLoading) {
    return <p className="text-sm text-stone-400">Loading recent activity...</p>;
  }

  const recent = (tickets ?? []).slice(0, 5);

  if (recent.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-stone-200 p-6 text-center">
        <p className="text-sm text-stone-500">No tickets yet. Submit one to get started.</p>
      </div>
    );
  }

  return (
    <div>
      <h3 className="text-sm font-medium text-stone-500 uppercase tracking-wider mb-3">
        Recent Activity
      </h3>
      <div className="space-y-2">
        {recent.map((ticket) => (
          <Link
            key={ticket.ticket_id}
            href={`/tickets/${ticket.ticket_id}`}
            className="flex items-center justify-between rounded-xl border border-stone-100 bg-white p-3 hover:bg-stone-50 transition-colors"
          >
            <div className="flex items-center gap-3">
              <span className="text-xs font-mono text-stone-400">{ticket.ticket_id}</span>
              {ticket.category && <CategoryBadge category={ticket.category} />}
            </div>
            <StatusBadge status={ticket.status} />
          </Link>
        ))}
      </div>
    </div>
  );
}
```

**Step 3: Full ticket table with filters**

Create `frontend/components/dashboard/ticket-table.tsx`:

```tsx
"use client";

import { useState } from "react";
import Link from "next/link";
import { useTickets } from "@/lib/hooks";
import { StatusBadge } from "@/components/ticket/status-badge";
import { UrgencyIndicator } from "@/components/ticket/urgency-indicator";
import { CategoryBadge } from "@/components/ticket/category-badge";
import { Button } from "@/components/ui/button";
import type { TicketStatus, TicketCategory } from "@/lib/types";

const STATUS_OPTIONS: { value: TicketStatus | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "processing", label: "Processing" },
  { value: "awaiting_human_review", label: "Needs Review" },
  { value: "resolved", label: "Resolved" },
  { value: "escalated", label: "Escalated" },
];

const CATEGORY_OPTIONS: { value: TicketCategory | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "order_issue", label: "Order Issue" },
  { value: "return_request", label: "Return" },
  { value: "product_question", label: "Product Q" },
  { value: "billing", label: "Billing" },
  { value: "complaint", label: "Complaint" },
];

export function TicketTable() {
  const [statusFilter, setStatusFilter] = useState<TicketStatus | "all">("all");
  const [categoryFilter, setCategoryFilter] = useState<TicketCategory | "all">("all");

  const { data: tickets, isLoading } = useTickets({
    status: statusFilter === "all" ? undefined : statusFilter,
    category: categoryFilter === "all" ? undefined : categoryFilter,
  });

  return (
    <div>
      <h3 className="text-sm font-medium text-stone-500 uppercase tracking-wider mb-3">
        All Tickets
      </h3>

      {/* Filters */}
      <div className="flex flex-wrap gap-4 mb-4">
        <div className="flex gap-1">
          {STATUS_OPTIONS.map((opt) => (
            <Button
              key={opt.value}
              variant={statusFilter === opt.value ? "default" : "ghost"}
              size="sm"
              className="rounded-lg text-xs"
              onClick={() => setStatusFilter(opt.value)}
            >
              {opt.label}
            </Button>
          ))}
        </div>
        <div className="flex gap-1">
          {CATEGORY_OPTIONS.map((opt) => (
            <Button
              key={opt.value}
              variant={categoryFilter === opt.value ? "default" : "ghost"}
              size="sm"
              className="rounded-lg text-xs"
              onClick={() => setCategoryFilter(opt.value)}
            >
              {opt.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Table */}
      {isLoading ? (
        <p className="text-sm text-stone-400 py-4">Loading tickets...</p>
      ) : !tickets || tickets.length === 0 ? (
        <p className="text-sm text-stone-400 py-4">No tickets match your filters.</p>
      ) : (
        <div className="space-y-2">
          {tickets.map((ticket) => (
            <Link
              key={ticket.ticket_id}
              href={`/tickets/${ticket.ticket_id}`}
              className="flex items-center gap-4 rounded-xl border border-stone-100 bg-white p-4 hover:bg-stone-50 transition-colors"
            >
              <span className="text-xs font-mono text-stone-400 w-24 shrink-0">
                {ticket.ticket_id}
              </span>
              <StatusBadge status={ticket.status} />
              {ticket.category && <CategoryBadge category={ticket.category} />}
              <div className="ml-auto">
                {ticket.urgency && <UrgencyIndicator urgency={ticket.urgency} />}
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
```

**Step 4: Wire up the dashboard page**

Replace `frontend/app/page.tsx`:

```tsx
import { AttentionZone } from "@/components/dashboard/attention-zone";
import { ActivityFeed } from "@/components/dashboard/activity-feed";
import { TicketTable } from "@/components/dashboard/ticket-table";

export default function DashboardPage() {
  return (
    <div className="space-y-8">
      <AttentionZone />
      <ActivityFeed />
      <TicketTable />
    </div>
  );
}
```

**Step 5: Verify visually**

```bash
npm run dev
```

Visit `http://localhost:3000`. Dashboard should render (empty state if backend isn't running).

**Step 6: Commit**

```bash
git add frontend/components/dashboard/ frontend/app/page.tsx
git commit -m "feat: add dashboard with attention zone, activity feed, and ticket table"
```

---

## Task 6: Ticket Detail Page

**Files:**
- Create: `frontend/app/tickets/[id]/page.tsx`

**Step 1: Build ticket detail page**

Create `frontend/app/tickets/[id]/page.tsx`:

```tsx
"use client";

import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { useTicket, useTicketTrace, useReviewTicket } from "@/lib/hooks";
import { StatusBadge } from "@/components/ticket/status-badge";
import { UrgencyIndicator } from "@/components/ticket/urgency-indicator";
import { CategoryBadge } from "@/components/ticket/category-badge";
import { TraceTimeline } from "@/components/trace/trace-timeline";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Separator } from "@/components/ui/separator";

export default function TicketDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: ticket, isLoading } = useTicket(id);
  const { data: trace } = useTicketTrace(id);
  const reviewMutation = useReviewTicket();
  const [showTrace, setShowTrace] = useState(false);
  const [modifyMode, setModifyMode] = useState(false);
  const [modifiedResponse, setModifiedResponse] = useState("");

  if (isLoading || !ticket) {
    return <p className="text-sm text-stone-400">Loading ticket...</p>;
  }

  const isEscalated = ticket.status === "awaiting_human_review";

  async function handleReview(action: "approve" | "reject") {
    await reviewMutation.mutateAsync({ ticketId: id, req: { action } });
    router.push("/");
  }

  async function handleModify() {
    await reviewMutation.mutateAsync({
      ticketId: id,
      req: { action: "modify", modified_response: modifiedResponse },
    });
    router.push("/");
  }

  return (
    <div className="max-w-3xl space-y-6">
      {/* Back link */}
      <button onClick={() => router.back()} className="text-sm text-stone-400 hover:text-stone-600">
        ← Back
      </button>

      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <h1 className="text-xl font-semibold text-stone-900 font-mono">{ticket.ticket_id}</h1>
        <StatusBadge status={ticket.status} />
        {ticket.category && <CategoryBadge category={ticket.category} />}
        {ticket.urgency && <UrgencyIndicator urgency={ticket.urgency} />}
      </div>

      {/* Review panel for escalated tickets */}
      {isEscalated && (
        <Card className="border-amber-200 bg-amber-50/50 p-6 space-y-4">
          <div>
            <p className="text-sm font-medium text-amber-800 mb-1">Why this was escalated</p>
            <p className="text-sm text-stone-700">
              {ticket.internal_notes || "The AI needs your judgment on this one."}
            </p>
          </div>

          {ticket.resolution_action && (
            <div>
              <p className="text-sm font-medium text-stone-700 mb-1">Proposed action</p>
              <p className="text-lg font-semibold text-stone-900 capitalize">
                {ticket.resolution_action}
              </p>
            </div>
          )}

          {ticket.customer_response && (
            <div>
              <p className="text-sm font-medium text-stone-700 mb-1">AI-drafted response</p>
              <p className="text-sm text-stone-600 bg-white rounded-xl p-4 border border-stone-100">
                {ticket.customer_response}
              </p>
            </div>
          )}

          <Separator />

          {modifyMode ? (
            <div className="space-y-3">
              <Textarea
                value={modifiedResponse}
                onChange={(e) => setModifiedResponse(e.target.value)}
                rows={4}
                className="rounded-xl"
                placeholder="Write your modified response..."
              />
              <div className="flex gap-2">
                <Button
                  onClick={handleModify}
                  disabled={!modifiedResponse.trim() || reviewMutation.isPending}
                  className="rounded-xl"
                >
                  Send Modified Response
                </Button>
                <Button variant="ghost" onClick={() => setModifyMode(false)} className="rounded-xl">
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="flex gap-2">
              <Button
                onClick={() => handleReview("approve")}
                disabled={reviewMutation.isPending}
                className="bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl"
              >
                Approve
              </Button>
              <Button
                variant="outline"
                onClick={() => {
                  setModifiedResponse(ticket.customer_response ?? "");
                  setModifyMode(true);
                }}
                className="rounded-xl"
              >
                Modify
              </Button>
              <Button
                variant="outline"
                onClick={() => handleReview("reject")}
                disabled={reviewMutation.isPending}
                className="text-rose-600 border-rose-200 hover:bg-rose-50 rounded-xl"
              >
                Reject
              </Button>
            </div>
          )}
        </Card>
      )}

      {/* Customer message */}
      {ticket.customer_response !== undefined && (
        <>
          <Card className="p-5">
            <p className="text-sm font-medium text-stone-500 mb-2">Customer Response</p>
            <p className="text-sm text-stone-700 leading-relaxed">
              {ticket.customer_response ?? "No response generated yet."}
            </p>
          </Card>
        </>
      )}

      {/* Internal notes */}
      {ticket.internal_notes && (
        <Card className="p-5 bg-stone-50 border-dashed">
          <p className="text-sm font-medium text-stone-500 mb-2">Internal Notes</p>
          <p className="text-sm text-stone-600 leading-relaxed">{ticket.internal_notes}</p>
        </Card>
      )}

      {/* Trace toggle */}
      <div>
        <Button
          variant="ghost"
          onClick={() => setShowTrace(!showTrace)}
          className="text-stone-500 hover:text-stone-700 rounded-xl"
        >
          {showTrace ? "Hide" : "View"} Agent Trace
        </Button>
        {showTrace && trace && <TraceTimeline trace={trace} />}
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
git add frontend/app/tickets/
git commit -m "feat: add ticket detail page with review panel"
```

---

## Task 7: Agent Trace Timeline

**Files:**
- Create: `frontend/components/trace/trace-timeline.tsx`
- Create: `frontend/components/trace/trace-step.tsx`

**Step 1: Trace step component**

Create `frontend/components/trace/trace-step.tsx`:

```tsx
"use client";

import { useState } from "react";
import { cn, formatTraceTimeDelta } from "@/lib/utils";
import type { TraceEntry } from "@/lib/types";

const AGENT_COLORS: Record<string, string> = {
  supervisor: "bg-violet-500",
  triage: "bg-blue-500",
  order_lookup: "bg-cyan-500",
  policy: "bg-amber-500",
  resolution_decide: "bg-orange-500",
  resolution_threshold: "bg-orange-400",
  resolution_execute: "bg-orange-600",
  response: "bg-emerald-500",
};

const AGENT_LABELS: Record<string, string> = {
  supervisor: "Supervisor",
  triage: "Triage",
  order_lookup: "Order Lookup",
  policy: "Policy",
  resolution_decide: "Resolution",
  resolution_threshold: "Threshold Check",
  resolution_execute: "Execute",
  response: "Response",
};

export function TraceStep({
  entry,
  firstTimestamp,
  isLast,
}: {
  entry: TraceEntry;
  firstTimestamp: string;
  isLast: boolean;
}) {
  const [expanded, setExpanded] = useState(false);
  const color = AGENT_COLORS[entry.agent] ?? "bg-stone-400";
  const label = AGENT_LABELS[entry.agent] ?? entry.agent;
  const timeDelta = formatTraceTimeDelta(entry.timestamp, firstTimestamp);

  return (
    <div className="relative flex gap-4">
      {/* Timeline line */}
      {!isLast && (
        <div className="absolute left-[11px] top-6 bottom-0 w-0.5 bg-stone-200" />
      )}

      {/* Dot */}
      <div className={cn("mt-1.5 h-6 w-6 rounded-full shrink-0 flex items-center justify-center", color)}>
        <span className="text-[10px] text-white font-bold">
          {label.charAt(0)}
        </span>
      </div>

      {/* Content */}
      <div className="pb-6 flex-1 min-w-0">
        <button
          onClick={() => setExpanded(!expanded)}
          className="flex items-center gap-2 w-full text-left"
        >
          <span className="text-sm font-medium text-stone-900">{label}</span>
          <span className="text-xs text-stone-400">{timeDelta}</span>
          <span className="ml-auto text-xs text-stone-400">{expanded ? "−" : "+"}</span>
        </button>

        <p className="text-xs text-stone-500 mt-0.5 truncate">{entry.output_summary}</p>

        {expanded && (
          <div className="mt-2 space-y-2 rounded-xl bg-stone-50 p-3 text-xs">
            <div>
              <span className="font-medium text-stone-500">Input: </span>
              <span className="text-stone-600">{entry.input_summary}</span>
            </div>
            <div>
              <span className="font-medium text-stone-500">Output: </span>
              <span className="text-stone-600">{entry.output_summary}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
```

**Step 2: Trace timeline container**

Create `frontend/components/trace/trace-timeline.tsx`:

```tsx
import { TraceStep } from "./trace-step";
import type { TraceResponse } from "@/lib/types";

export function TraceTimeline({ trace }: { trace: TraceResponse }) {
  if (!trace.trace_log || trace.trace_log.length === 0) {
    return <p className="text-sm text-stone-400 mt-4">No trace data available.</p>;
  }

  const firstTimestamp = trace.trace_log[0].timestamp;

  return (
    <div className="mt-4 rounded-2xl border border-stone-200 bg-white p-5">
      <h3 className="text-sm font-medium text-stone-500 uppercase tracking-wider mb-4">
        Agent Trace
      </h3>
      <div>
        {trace.trace_log.map((entry, i) => (
          <TraceStep
            key={`${entry.agent}-${entry.timestamp}-${i}`}
            entry={entry}
            firstTimestamp={firstTimestamp}
            isLast={i === trace.trace_log.length - 1}
          />
        ))}
      </div>
    </div>
  );
}
```

**Step 3: Commit**

```bash
git add frontend/components/trace/
git commit -m "feat: add agent trace timeline with expandable steps"
```

---

## Task 8: Focused Review Flow

**Files:**
- Create: `frontend/app/review/page.tsx`
- Create: `frontend/components/review/review-card.tsx`

**Step 1: Review card component**

Create `frontend/components/review/review-card.tsx`:

```tsx
"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { useReviewTicket, useTicketTrace } from "@/lib/hooks";
import { StatusBadge } from "@/components/ticket/status-badge";
import { UrgencyIndicator } from "@/components/ticket/urgency-indicator";
import { CategoryBadge } from "@/components/ticket/category-badge";
import { TraceTimeline } from "@/components/trace/trace-timeline";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Separator } from "@/components/ui/separator";
import type { Ticket } from "@/lib/types";

export function ReviewCard({
  ticket,
  onComplete,
}: {
  ticket: Ticket;
  onComplete: () => void;
}) {
  const reviewMutation = useReviewTicket();
  const { data: trace } = useTicketTrace(ticket.ticket_id);
  const [modifyMode, setModifyMode] = useState(false);
  const [modifiedResponse, setModifiedResponse] = useState("");
  const [showTrace, setShowTrace] = useState(false);

  async function handleAction(action: "approve" | "reject") {
    await reviewMutation.mutateAsync({
      ticketId: ticket.ticket_id,
      req: { action },
    });
    onComplete();
  }

  async function handleModify() {
    await reviewMutation.mutateAsync({
      ticketId: ticket.ticket_id,
      req: { action: "modify", modified_response: modifiedResponse },
    });
    onComplete();
  }

  return (
    <motion.div
      initial={{ opacity: 0, x: 40 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: -40 }}
      transition={{ duration: 0.3, ease: "easeOut" }}
      className="max-w-2xl mx-auto space-y-6"
    >
      {/* Header */}
      <div className="flex items-center gap-3 flex-wrap">
        <span className="text-sm font-mono text-stone-400">{ticket.ticket_id}</span>
        <StatusBadge status={ticket.status} />
        {ticket.category && <CategoryBadge category={ticket.category} />}
        {ticket.urgency && <UrgencyIndicator urgency={ticket.urgency} />}
      </div>

      {/* Escalation reason — shown FIRST */}
      <Card className="border-amber-200 bg-amber-50/50 p-5">
        <p className="text-sm font-medium text-amber-800 mb-1">Why this needs your review</p>
        <p className="text-sm text-stone-700 leading-relaxed">
          {ticket.internal_notes || "The AI needs your judgment on this one."}
        </p>
      </Card>

      {/* Proposed action */}
      {ticket.resolution_action && (
        <div className="text-center py-2">
          <p className="text-xs text-stone-500 uppercase tracking-wider">Proposed Action</p>
          <p className="text-2xl font-semibold text-stone-900 capitalize mt-1">
            {ticket.resolution_action}
          </p>
        </div>
      )}

      {/* AI-drafted response */}
      {ticket.customer_response && (
        <Card className="p-5">
          <p className="text-sm font-medium text-stone-500 mb-2">AI-drafted customer response</p>
          <p className="text-sm text-stone-700 leading-relaxed">{ticket.customer_response}</p>
        </Card>
      )}

      <Separator />

      {/* Action buttons */}
      {modifyMode ? (
        <div className="space-y-3">
          <Textarea
            value={modifiedResponse}
            onChange={(e) => setModifiedResponse(e.target.value)}
            rows={4}
            className="rounded-xl"
            autoFocus
          />
          <div className="flex gap-2">
            <Button
              onClick={handleModify}
              disabled={!modifiedResponse.trim() || reviewMutation.isPending}
              className="rounded-xl"
            >
              Send Modified Response
            </Button>
            <Button variant="ghost" onClick={() => setModifyMode(false)} className="rounded-xl">
              Cancel
            </Button>
          </div>
        </div>
      ) : (
        <div className="flex justify-center gap-3">
          <Button
            onClick={() => handleAction("approve")}
            disabled={reviewMutation.isPending}
            size="lg"
            className="bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl min-w-[120px]"
          >
            Approve
          </Button>
          <Button
            variant="outline"
            size="lg"
            onClick={() => {
              setModifiedResponse(ticket.customer_response ?? "");
              setModifyMode(true);
            }}
            className="rounded-xl min-w-[120px]"
          >
            Modify
          </Button>
          <Button
            variant="outline"
            size="lg"
            onClick={() => handleAction("reject")}
            disabled={reviewMutation.isPending}
            className="text-rose-600 border-rose-200 hover:bg-rose-50 rounded-xl min-w-[120px]"
          >
            Reject
          </Button>
        </div>
      )}

      {/* Trace toggle */}
      <div className="pt-2">
        <Button
          variant="ghost"
          onClick={() => setShowTrace(!showTrace)}
          className="text-stone-400 hover:text-stone-600 text-xs rounded-xl"
        >
          {showTrace ? "Hide" : "View"} Agent Trace
        </Button>
        {showTrace && trace && <TraceTimeline trace={trace} />}
      </div>
    </motion.div>
  );
}
```

**Step 2: Review flow page with auto-advance**

Create `frontend/app/review/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { useEscalatedTickets } from "@/lib/hooks";
import { ReviewCard } from "@/components/review/review-card";
import { Button } from "@/components/ui/button";

export default function ReviewPage() {
  const router = useRouter();
  const { data: tickets, isLoading } = useEscalatedTickets();
  const [currentIndex, setCurrentIndex] = useState(0);

  if (isLoading) {
    return <p className="text-center text-sm text-stone-400 mt-20">Loading...</p>;
  }

  if (!tickets || tickets.length === 0) {
    return (
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="text-center mt-20"
      >
        <p className="text-4xl mb-3">✓</p>
        <h1 className="text-2xl font-semibold text-stone-900 mb-2">All caught up</h1>
        <p className="text-sm text-stone-500 mb-6">No tickets need your review.</p>
        <Button variant="outline" onClick={() => router.push("/")} className="rounded-xl">
          Back to Dashboard
        </Button>
      </motion.div>
    );
  }

  // All reviewed in this session
  if (currentIndex >= tickets.length) {
    return (
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="text-center mt-20"
      >
        <p className="text-4xl mb-3">✓</p>
        <h1 className="text-2xl font-semibold text-stone-900 mb-2">All caught up</h1>
        <p className="text-sm text-stone-500 mb-6">
          You reviewed {tickets.length} {tickets.length === 1 ? "ticket" : "tickets"}.
        </p>
        <Button variant="outline" onClick={() => router.push("/")} className="rounded-xl">
          Back to Dashboard
        </Button>
      </motion.div>
    );
  }

  const currentTicket = tickets[currentIndex];
  const total = tickets.length;

  return (
    <div>
      {/* Progress bar */}
      <div className="max-w-2xl mx-auto mb-8">
        <div className="flex items-center justify-between text-xs text-stone-500 mb-2">
          <span>Review {currentIndex + 1} of {total}</span>
          <button
            onClick={() => setCurrentIndex((i) => Math.min(i + 1, total))}
            className="hover:text-stone-700"
          >
            Skip →
          </button>
        </div>
        <div className="h-1.5 bg-stone-100 rounded-full overflow-hidden">
          <motion.div
            className="h-full bg-amber-500 rounded-full"
            initial={{ width: 0 }}
            animate={{ width: `${((currentIndex) / total) * 100}%` }}
            transition={{ duration: 0.3 }}
          />
        </div>
      </div>

      {/* Current ticket */}
      <AnimatePresence mode="wait">
        <ReviewCard
          key={currentTicket.ticket_id}
          ticket={currentTicket}
          onComplete={() => setCurrentIndex((i) => i + 1)}
        />
      </AnimatePresence>
    </div>
  );
}
```

**Step 3: Commit**

```bash
git add frontend/app/review/ frontend/components/review/
git commit -m "feat: add focused review flow with auto-advance and Framer Motion transitions"
```

---

## Task 9: Submit Ticket Form

**Files:**
- Create: `frontend/app/submit/page.tsx`

**Step 1: Build submit page**

Create `frontend/app/submit/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useCreateTicket } from "@/lib/hooks";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { CUSTOMERS } from "@/lib/types";

export default function SubmitPage() {
  const router = useRouter();
  const createMutation = useCreateTicket();
  const [customerId, setCustomerId] = useState(CUSTOMERS[0].id);
  const [message, setMessage] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const ticket = await createMutation.mutateAsync({
      customer_id: customerId,
      message,
    });
    router.push(`/tickets/${ticket.ticket_id}`);
  }

  const selectedCustomer = CUSTOMERS.find((c) => c.id === customerId);

  return (
    <div className="max-w-lg mx-auto">
      <h1 className="text-xl font-semibold text-stone-900 mb-6">Submit a Ticket</h1>

      <Card className="p-6">
        <form onSubmit={handleSubmit} className="space-y-5">
          {/* Customer selector */}
          <div>
            <label className="text-sm font-medium text-stone-700 mb-2 block">Customer</label>
            <div className="grid grid-cols-2 gap-2">
              {CUSTOMERS.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setCustomerId(c.id)}
                  className={`rounded-xl border p-3 text-left text-sm transition-colors ${
                    customerId === c.id
                      ? "border-stone-900 bg-stone-50"
                      : "border-stone-200 hover:border-stone-300"
                  }`}
                >
                  <p className="font-medium text-stone-900">{c.name}</p>
                  <p className="text-xs text-stone-500">{c.tier} · {c.id}</p>
                </button>
              ))}
            </div>
          </div>

          {/* Message */}
          <div>
            <label className="text-sm font-medium text-stone-700 mb-2 block">Message</label>
            <Textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={4}
              placeholder="e.g., I want to return the wireless headphones from order ORD-001"
              className="rounded-xl"
            />
          </div>

          {/* Submit */}
          <Button
            type="submit"
            disabled={!message.trim() || createMutation.isPending}
            className="w-full rounded-xl"
          >
            {createMutation.isPending ? "Submitting..." : "Submit Ticket"}
          </Button>

          {createMutation.isError && (
            <p className="text-sm text-rose-600">
              Failed to submit. Is the backend running on port 8000?
            </p>
          )}
        </form>
      </Card>
    </div>
  );
}
```

**Step 2: Commit**

```bash
git add frontend/app/submit/
git commit -m "feat: add submit ticket page with customer selector"
```

---

## Task 10: Tailwind Warm Theme & Polish

**Files:**
- Modify: `frontend/tailwind.config.ts` — extend with warm color overrides if needed
- Modify: `frontend/app/globals.css` — clean up default styles

**Step 1: Clean up global CSS**

Replace the default globals.css content (keep Tailwind directives, remove Next.js defaults):

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  body {
    @apply antialiased text-stone-900;
  }
}
```

**Step 2: Verify the full app visually**

```bash
npm run dev
```

Walk through all pages:
- Dashboard: `http://localhost:3000`
- Submit: `http://localhost:3000/submit`
- Review: `http://localhost:3000/review`

**Step 3: Commit**

```bash
git add frontend/tailwind.config.ts frontend/app/globals.css
git commit -m "feat: apply warm theme and clean up default styles"
```

---

## Task 11: Jest Config & Final Tests

**Files:**
- Create: `frontend/jest.config.ts`
- Verify: `frontend/__tests__/lib/utils.test.ts`

**Step 1: Configure Jest for Next.js**

Create `frontend/jest.config.ts`:

```typescript
import type { Config } from "jest";
import nextJest from "next/jest";

const createJestConfig = nextJest({ dir: "./" });

const config: Config = {
  testEnvironment: "jsdom",
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1",
  },
};

export default createJestConfig(config);
```

Add to `frontend/package.json` scripts:

```json
"test": "jest"
```

**Step 2: Run tests**

```bash
cd frontend && npm test
```

**Step 3: Run build to verify no type errors**

```bash
npm run build
```

**Step 4: Final commit**

```bash
git add frontend/jest.config.ts frontend/package.json
git commit -m "feat: add Jest config and verify build"
```

---

## Summary

| Task | What | Commit |
|------|------|--------|
| 1 | Scaffold Next.js + deps | `feat: scaffold Next.js frontend...` |
| 2 | Types, API client, utils | `feat: add TypeScript types, API client...` |
| 3 | Query hooks, providers, app shell | `feat: add TanStack Query hooks...` |
| 4 | Badge components | `feat: add status, urgency, category badges` |
| 5 | Dashboard page | `feat: add dashboard with attention zone...` |
| 6 | Ticket detail page | `feat: add ticket detail page with review panel` |
| 7 | Agent trace timeline | `feat: add agent trace timeline...` |
| 8 | Focused review flow | `feat: add focused review flow...` |
| 9 | Submit ticket form | `feat: add submit ticket page...` |
| 10 | Theme & polish | `feat: apply warm theme...` |
| 11 | Jest config & build verify | `feat: add Jest config...` |
