import type { ReactNode } from "react";
import benchmark from "../public/benchmarks/notch-agent-automation-2026-10-20.json";
import AgentSetup from "./agent-setup";
import AgentSetupLink from "./agent-setup-link";
import Reveal from "./reveal";

const { notch, codex } = benchmark.controlledForm;
const speedup = Math.round(codex.medianMs / notch.medianMs);

const features: { title: string; description: string; icon: ReactNode }[] = [
  {
    title: "Already signed in.",
    description: "Your agent uses real tabs and your existing sessions. No separate browser profile to set up.",
    icon: <><rect x="3" y="4" width="18" height="16" rx="3" /><path d="M3 9h18M7 6.5h.01M10 6.5h.01m0 8 2 2 4-4" /></>,
  },
  {
    title: "Works in the background.",
    description: "Keep the notch collapsed while your agent works. Run tasks in two independent tabs at once.",
    icon: <><rect x="3" y="3" width="13" height="13" rx="3" /><path d="M8 20h10a3 3 0 0 0 3-3V8M7 9h5m-2-2 2 2-2 2" /></>,
  },
  {
    title: "Reads what matters.",
    description: "Extract text, links, and media. Get focused page snapshots, with support for embedded frames.",
    icon: <><path d="M8 3H5a2 2 0 0 0-2 2v3m13-5h3a2 2 0 0 1 2 2v3M3 16v3a2 2 0 0 0 2 2h3m13-5v3a2 2 0 0 1-2 2h-3M8 8h8M8 12h8M8 16h5" /></>,
  },
  {
    title: "Acts on the page.",
    description: "Click, fill forms, select options, and upload files you choose. Everyday browser tasks, ready for your agent.",
    icon: <><path d="m5 3 14 9-7 1-3 7L5 3Z" /><path d="m13 14 4 6" /></>,
  },
  {
    title: "More than text.",
    description: "Capture screenshots and video frames, or open a local HTML result right in the notch.",
    icon: <><rect x="3" y="4" width="18" height="16" rx="3" /><path d="m3 16 5-5 4 4 3-3 6 6" /><circle cx="16" cy="8" r="1.5" /></>,
  },
  {
    title: "Always in your control.",
    description: "See agent activity, stop or resume control, and take over whenever a site needs you.",
    icon: <><path d="M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6l-8-3Z" /><path d="M10 9v6m4-6v6" /></>,
  },
];

function AgentBenchmark() {
  return (
    <div className="overflow-hidden rounded-3xl bg-[#f5f6f8]">
      <div className="grid gap-8 px-6 py-8 sm:grid-cols-[1fr_1.2fr] sm:items-center sm:gap-12 sm:px-9 sm:py-10 lg:gap-20 lg:px-12">
        <div>
          <p className="bg-linear-to-br from-[#123b57] to-[#6b91ad] bg-clip-text text-[88px] font-semibold leading-[0.95] tracking-[-0.08em] text-transparent sm:text-[100px]">
            {speedup}<span className="ml-1 text-[0.68em]">×</span>
          </p>
          <h3 className="mt-4 max-w-64 text-balance text-[20px] font-medium leading-[1.3] tracking-[-0.035em] text-[#263e50]">
            faster in our local form automation test.
          </h3>
        </div>

        <figure className="min-w-0" aria-labelledby="agent-benchmark-caption">
          <figcaption id="agent-benchmark-caption" className="mb-6 text-[12px] text-[#6e6e73]">Time to complete · lower is better</figcaption>
          <div className="space-y-6">
            {[
              { label: "Notch Browser", result: notch, color: "bg-[#446c8b]" },
              { label: "Codex in-app browser", result: codex, color: "bg-[#d3d7dd]" },
            ].map(({ label, result, color }) => (
              <div key={label}>
                <div className="mb-2 flex items-baseline justify-between gap-3 text-[13px] leading-5">
                  <span className="font-medium text-[#424245]">{label}</span>
                  <span className="shrink-0 tabular-nums text-[#6e6e73]">{Math.round(result.medianMs)} ms</span>
                </div>
                <div className="h-3" aria-hidden="true">
                  <div className={`h-full rounded-full ${color}`} style={{ width: `${result.medianMs / codex.medianMs * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
          <p className="mt-6 text-[11px] leading-5 text-[#6e6e73]">Median of {notch.samples} runs per browser. {notch.successes}/{notch.samples} completed in both.<br />Browser execution only; excludes AI thinking and setup.</p>
        </figure>
      </div>

      <details className="group/benchmark border-t border-[#e2e5e9] px-6 sm:px-9 lg:px-12">
        <summary className="flex min-h-14 cursor-pointer list-none items-center justify-between gap-4 text-[12px] text-[#6e6e73] [&::-webkit-details-marker]:hidden">
          <span>How we measured</span>
          <span className="text-lg font-light transition-transform group-open/benchmark:rotate-45" aria-hidden="true">+</span>
        </summary>
        <div className="grid gap-4 pb-6 text-[12px] leading-[1.75] text-[#6e6e73] sm:grid-cols-2 sm:gap-8">
          <p>October 20, 2026 · Apple M4 Pro · macOS 26.0. Both browsers navigated to the same local form, filled three fields, selected an option, checked a box, submitted, and verified the saved result. Same 870 × 262 viewport; two warmups per browser excluded.</p>
          <div>
            <p>Browser API execution only; excludes AI thinking, setup, and app startup. Notch used its JavaScript client; Codex used its in-app Playwright API. Different automation drivers, one local task. Results vary by workflow.</p>
            <a href="/benchmarks/notch-agent-automation-2026-10-20.json" download className="mt-3 inline-flex min-h-8 items-center gap-1 text-[#335a79] underline underline-offset-4 hover:text-[#123b57]">Download timing data <span aria-hidden="true">↓</span></a>
          </div>
        </div>
      </details>
    </div>
  );
}

export default function AgentFeatures() {
  return (
    <article id="agents" className="feature-story scroll-mt-10 sm:scroll-mt-16" aria-labelledby="agents-title">
      <Reveal className="landing-container feature-heading">
        <p className="landing-eyebrow">Built for your AI agent</p>
        <h2 id="agents-title" className="landing-heading bg-linear-to-r from-[#0b2f49] from-25% to-[#658fb1] to-80% bg-clip-text text-transparent">Your browser.<br />Your agent’s, too.</h2>
        <p className="mx-auto mt-5 max-w-[570px] text-pretty text-[14px] font-medium leading-[1.7] tracking-[-0.025em] text-[#86868b] sm:text-[15px]">Let Codex or Claude Code research, collect, and act on the web. In the same little browser you use, with your logins and your control.</p>
        <AgentSetupLink />
      </Reveal>

      <Reveal className="landing-container mt-7 sm:mt-9">
        <AgentBenchmark />
      </Reveal>

      <Reveal className="landing-container mt-10 sm:mt-12">
        <ul className="grid gap-x-8 gap-y-8 sm:grid-cols-2 sm:gap-y-10 md:grid-cols-3 lg:gap-x-14">
          {features.map(({ title, description, icon }) => (
            <li key={title} className="min-w-0">
              <svg className="mb-3 size-6 text-[#52738e]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{icon}</svg>
              <h3 className="text-[16px] font-semibold leading-6 tracking-[-0.035em] text-[#1d1d1f]">{title}</h3>
              <p className="mt-2 max-w-[320px] text-pretty text-[13px] leading-[1.7] tracking-[-0.015em] text-[#6e6e73]">{description}</p>
            </li>
          ))}
        </ul>
        <p className="mt-7 text-[11px] leading-5 text-[#86868b]">For background tasks, keep the app running and your Mac awake.</p>
      </Reveal>

      <Reveal className="landing-container mt-7 sm:mt-8">
        <details id="agent-setup" className="group/setup scroll-mt-12 border-y border-[#e5e5e9]">
          <summary className="flex min-h-16 cursor-pointer list-none items-center justify-between gap-4 text-[13px] font-medium text-[#424245] sm:text-[14px] [&::-webkit-details-marker]:hidden">
            <span>Set up your agent</span>
            <span className="ml-auto text-[10px] font-normal text-[#86868b] sm:text-[11px]">CLI + skills included</span>
            <span className="text-xl font-normal text-[#86868b] transition-transform group-open/setup:rotate-45" aria-hidden="true">+</span>
          </summary>
          <div className="grid items-start gap-6 pb-8 pt-3 md:grid-cols-[0.85fr_1.4fr] md:gap-10" aria-labelledby="agent-setup-title">
            <div className="max-w-[340px] pt-1">
              <h3 id="agent-setup-title" className="text-balance text-[26px] font-semibold leading-[1.15] tracking-[-0.045em] sm:text-[28px]">One setup.<br />Then just ask.</h3>
              <p className="mt-3 text-[13px] leading-[1.7] tracking-[-0.02em] text-[#6e6e73]">The CLI, JavaScript client, and agent skills come with the Mac app. Connect once, then ask for what you need in plain language.</p>
              <ol className="mt-5 grid gap-3 text-[12px] leading-[1.6] text-[#53535b]">
                {["Install and activate Notch Browser.", "Run the setup command for your agent.", "Start a new agent session and ask."].map((step, index) => (
                  <li key={step} className="flex items-baseline gap-2.5"><span className="text-[11px] tabular-nums text-[#a1a1a7]" aria-hidden="true">0{index + 1}</span>{step}</li>
                ))}
              </ol>
              <a href="/skills/notch-browser/SKILL.md" download="SKILL.md" className="mt-5 inline-flex min-h-9 items-center gap-1 text-[12px] text-[#335a79] underline underline-offset-4 hover:text-[#123b57]">Download the agent skill <span aria-hidden="true">↓</span></a>
            </div>
            <AgentSetup />
          </div>
        </details>
      </Reveal>
    </article>
  );
}
