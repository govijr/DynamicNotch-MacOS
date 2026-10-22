import type { ReactNode } from "react";
import benchmark from "../public/benchmarks/notch-agent-automation-2026-10-20.json";
import Reveal from "./reveal";

const { notch, codex } = benchmark.controlledForm;
const speedup = Math.round(codex.medianMs / notch.medianMs);

const features: { title: string; description: string; icon: ReactNode }[] = [
  {
    title: "Already signed in.",
    description: "Use your tabs and existing logins.",
    icon: <><rect x="3" y="4" width="18" height="16" rx="3" /><path d="M3 9h18M7 6.5h.01M10 6.5h.01m0 8 2 2 4-4" /></>,
  },
  {
    title: "Works in the background.",
    description: "Let your agent work with the notch collapsed.",
    icon: <><rect x="3" y="3" width="13" height="13" rx="3" /><path d="M8 20h10a3 3 0 0 0 3-3V8M7 9h5m-2-2 2 2-2 2" /></>,
  },
  {
    title: "Reads what matters.",
    description: "Read page content, links, and embedded frames.",
    icon: <><path d="M8 3H5a2 2 0 0 0-2 2v3m13-5h3a2 2 0 0 1 2 2v3M3 16v3a2 2 0 0 0 2 2h3m13-5v3a2 2 0 0 1-2 2h-3M8 8h8M8 12h8M8 16h5" /></>,
  },
  {
    title: "Acts on the page.",
    description: "Click, fill forms, and upload files you choose.",
    icon: <><path d="m5 3 14 9-7 1-3 7L5 3Z" /><path d="m13 14 4 6" /></>,
  },
  {
    title: "More than text.",
    description: "Capture screenshots or open local HTML.",
    icon: <><rect x="3" y="4" width="18" height="16" rx="3" /><path d="m3 16 5-5 4 4 3-3 6 6" /><circle cx="16" cy="8" r="1.5" /></>,
  },
  {
    title: "Always in your control.",
    description: "Stop, resume, or take over whenever you need.",
    icon: <><path d="M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6l-8-3Z" /><path d="M10 9v6m4-6v6" /></>,
  },
];

export function AgentBenchmark() {
  return (
    <section id="agent-benchmark" className="-mt-12 landing-container agent-benchmark-section" aria-labelledby="agent-benchmark-title">
      <Reveal className="overflow-hidden rounded-3xl bg-[#f5f6f8]">
        <div className="grid gap-8 px-6 py-8 sm:grid-cols-[1fr_1.2fr] sm:items-center sm:gap-12 sm:px-9 sm:py-10 lg:gap-20 lg:px-12">
          <div>
            <p className="landing-eyebrow">Agent benchmark</p>
            <h2 id="agent-benchmark-title" className="agent-benchmark-heading bg-linear-to-br from-[#123b57] to-[#6b91ad] bg-clip-text text-transparent">
              {speedup}× faster.
            </h2>
            <p className="mt-5 max-w-[340px] text-pretty text-[13px] leading-[1.7] text-[#6e6e73]">Browser execution in our local form automation test. Median of {notch.samples} runs.</p>
          </div>

          <figure className="min-w-0" aria-labelledby="agent-benchmark-caption">
            <figcaption id="agent-benchmark-caption" className="mb-6 text-[12px] text-[#6e6e73]">Time to complete · lower is better</figcaption>
            <div className="space-y-6">
              {[
                { label: "Ink", result: notch, color: "bg-[#446c8b]" },
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
            <p className="mt-6 text-[11px] leading-5 text-[#6e6e73]">Browser execution only; excludes AI thinking and setup.</p>
          </figure>
        </div>

        {/* <details className="group/benchmark border-t border-[#e2e5e9] px-6 sm:px-9 lg:px-12">
          <summary className="flex min-h-14 cursor-pointer list-none items-center justify-between gap-4 text-[12px] text-[#6e6e73] [&::-webkit-details-marker]:hidden">
            <span>How we measured</span>
            <span className="text-lg font-light transition-transform group-open/benchmark:rotate-45" aria-hidden="true">+</span>
          </summary>
          <div className="grid gap-4 pb-6 text-[12px] leading-[1.75] text-[#6e6e73] sm:grid-cols-2 sm:gap-8">
            <p>October 20, 2026 · Apple M4 Pro · macOS 26.0. Both browsers navigated to the same local form, filled three fields, selected an option, checked a box, submitted, and verified the saved result. Same 870 × 262 viewport; two warmups per browser excluded. Median of {notch.samples} runs per browser; {notch.successes}/{notch.samples} completed in both.</p>
            <div>
              <p>Browser API execution only; excludes AI thinking, setup, and app startup. Ink used its JavaScript client; Codex used its in-app Playwright API. Different automation drivers, one local task. Results vary by workflow.</p>
              <a href="/benchmarks/notch-agent-automation-2026-10-20.json" download className="mt-3 inline-flex min-h-8 items-center gap-1 text-[#335a79] underline underline-offset-4 hover:text-[#123b57]">Download timing data <span aria-hidden="true">↓</span></a>
            </div>
          </div>
        </details> */}
      </Reveal>
    </section>
  );
}

export default function AgentFeatures() {
  return (
    <article id="agents" className="feature-story scroll-mt-10 sm:scroll-mt-16" aria-labelledby="agents-title">
      <Reveal className="landing-container feature-heading">
        <p className="landing-eyebrow">AI agents</p>
        <h2 id="agents-title" className="landing-heading text-black">Your browser. <br/> Your agent&apos;s, too.</h2>
        <p className="feature-description">Let your coding agent browse, interact, and get things done using Ink.</p>
        {/* <p className="mt-3 text-[13px] leading-6 text-[#86868b]">Connect during onboarding. No Terminal needed.</p> */}
      </Reveal>

      <Reveal className="landing-container mt-10 sm:mt-12">
        <ul className="grid gap-x-8 gap-y-8 sm:grid-cols-2 sm:gap-y-10 md:grid-cols-3 lg:gap-x-14 mx-12">
          {features.map(({ title, description, icon }) => (
            <li key={title} className="min-w-0 flex flex-col items-center justify-center">
              <svg className="mb-3 block size-6 text-[#52738e]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{icon}</svg>
              <h3 className="text-[16px] font-semibold leading-6 tracking-[-0.035em] text-[#1d1d1f]">{title}</h3>
              <p className="mt-2 max-w-[320px] text-pretty text-[13px] leading-[1.7] tracking-[-0.015em] text-[#6e6e73]">{description}</p>
            </li>
          ))}
        </ul>
        {/* <p className="mt-7 text-[11px] leading-5 text-[#86868b]">For background tasks, keep the app running and your Mac awake.</p> */}
      </Reveal>
    </article>
  );
}
