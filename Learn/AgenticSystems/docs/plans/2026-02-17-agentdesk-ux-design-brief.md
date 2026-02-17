# AgentDesk — Design Brief

## What This Is

An AI-powered customer support dashboard. AI agents automatically handle most tickets (refunds, product questions, returns). When the AI isn't confident enough, it pauses and asks a human to approve, modify, or reject its recommendation.

The backend is built. We need the frontend.

## The Feeling

**"Calm partner, not control panel."** A support manager opens this, sees what needs their attention, handles it in under 2 minutes, and moves on. The system respects their time and their judgment.

Warm, human-centered, approachable — not cold SaaS. Think Intercom meets Linear.

## The One Interaction That Matters Most

**Reviewing escalated tickets.** This is the core workflow:

1. The AI escalated a ticket because it couldn't auto-resolve (refund too large, complaint, edge case)
2. The reviewer sees WHY it was escalated, what the AI recommends, and the drafted response
3. They approve, modify, or reject — and the next ticket appears automatically
4. Progress bar shows "2 of 5" so there's a finish line

**Key constraint:** The escalation reason must be seen BEFORE the action buttons. We don't want rubber-stamping.

## The Four Views

1. **Dashboard** — "Do I need to do anything?" Escalated tickets prominent at top. Recent AI activity below. Full ticket list with filters at bottom.
2. **Focused Review Flow** — One escalated ticket at a time, full context, auto-advance after each decision. This is the hero interaction.
3. **Ticket Detail** — Full view of any ticket: customer message, AI response, internal notes, status. Link to the trace view.
4. **Agent Trace** — Timeline showing which AI agents ran and what they decided. Each step expandable. This is what makes the AI trustworthy — treat it as a feature, not a debug panel.
5. **Submit Ticket** — Simple form (customer dropdown + message) for testing.

## Non-Negotiable Constraints

- Escalation reason shown before action buttons (prevent automation bias)
- Modify must be as easy as Approve (pre-filled editor, not a blank textarea)
- Status indicators work without color alone (accessibility)
- Never show raw data — format everything for humans ("$79.99", "3 min ago", not timestamps or JSON)
- Agent trace accessible from every ticket in one tap

## Everything Else Is Yours

Layout, color palette, typography, component library, animations, card vs table vs kanban, drawer vs page, icon style, empty states, how the trace view is visualized — all creative decisions for the designer.

The full PRD (docs/AgentDesk-PRD.md) has detailed API shapes, seed data, example scenarios, and a deep section on the psychology of human-AI supervision (Sections 9.1–9.7) that's worth reading for inspiration.
