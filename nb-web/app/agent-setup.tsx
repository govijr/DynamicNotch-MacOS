"use client";

import { useEffect, useRef, useState } from "react";

const agents = [
  { id: "codex", label: "Codex", skillPath: "~/.codex/skills/notch-browser" },
  { id: "claude", label: "Claude Code", skillPath: "~/.claude/skills/notch-browser" },
  { id: "all", label: "Both", skillPath: "Both agent skill folders" },
] as const;

type AgentID = (typeof agents)[number]["id"];
const appPath = "/Applications/notch-browser.app";

function CopyIcon({ copied }: { copied: boolean }) {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {copied ? <path d="m5 12 4 4L19 6" /> : <><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V4a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h4" /></>}
    </svg>
  );
}

export default function AgentSetup() {
  const [agent, setAgent] = useState<AgentID>("codex");
  const [copyState, setCopyState] = useState<"idle" | "copied" | "error">("idle");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const selected = agents.find((option) => option.id === agent)!;
  const command = `cd "${appPath}"\n./Contents/Helpers/notch-browser setup ${agent}`;

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  function selectAgent(id: AgentID) {
    if (timer.current) clearTimeout(timer.current);
    setAgent(id);
    setCopyState("idle");
  }

  async function copyCommand() {
    if (timer.current) clearTimeout(timer.current);
    try {
      await navigator.clipboard.writeText(command);
      setCopyState("copied");
      timer.current = setTimeout(() => setCopyState("idle"), 2500);
    } catch {
      setCopyState("error");
    }
  }

  return (
    <div className="min-w-0 pt-1">
      <div className="flex flex-wrap gap-6 border-b border-[#e6e6e6]" role="group" aria-label="Choose your agent">
        {agents.map((option) => (
          <button key={option.id} type="button" aria-pressed={agent === option.id} onClick={() => selectAgent(option.id)} className={`-mb-px min-h-11 cursor-pointer border-b-2 text-[14px] font-medium transition-colors ${agent === option.id ? "border-[#111] text-[#111]" : "border-transparent text-[#888] hover:text-[#111]"}`}>
            {option.label}
          </button>
        ))}
      </div>

      <p className="mb-3 mt-6 text-[13px] text-[#777]">Paste this into Terminal once:</p>
      <div className="overflow-hidden rounded-xl border border-[#e5e5e5] bg-[#f6f6f6]">
        <div className="flex items-center justify-between gap-3 px-4 pt-3">
          <span className="flex items-center gap-2 text-[11px] font-medium text-[#999]"><span aria-hidden="true">&gt;_</span> Terminal</span>
          <button type="button" onClick={copyCommand} className="flex min-h-8 cursor-pointer items-center gap-2 rounded px-2 text-[12px] font-medium text-[#555] transition-colors hover:bg-[#f5f5f5] hover:text-[#111]" aria-label={`Copy ${selected.label} setup command`}>
            <CopyIcon copied={copyState === "copied"} />
            {copyState === "copied" ? "Copied" : "Copy"}
          </button>
        </div>
        <pre className="whitespace-pre-wrap break-words px-5 pb-5 pt-3 text-[12px] leading-6 text-[#333]"><code>{command}</code></pre>
      </div>
      <p className="mt-2 min-h-5 text-[12px] text-[#777]" role="status">
        {copyState === "copied" ? "Command copied. Ready to paste into Terminal." : copyState === "error" ? "Select the command above and copy it manually." : "Installs the CLI and your chosen agent skill."}
      </p>

      <div className="mt-7">
        <p className="text-[13px] font-medium">Then start a new agent session and ask:</p>
        <p className="agent-setup-prompt mt-3 text-[14px] leading-6 text-[#777]">“Use Notch Browser to find the WebKit docs. Work in the background.”</p>
      </div>

      <details className="group mt-5 text-[12px] leading-5 text-[#777]">
        <summary className="flex w-fit cursor-pointer list-none items-center gap-2 font-medium text-[#555]">What gets installed?<span className="transition-transform group-open:rotate-45" aria-hidden="true">+</span></summary>
        <dl className="mt-3 grid gap-3">
          <div><dt className="font-medium text-[#333]">CLI</dt><dd className="mt-0.5 break-all font-mono text-[11px]">~/.local/bin/notch-browser</dd></div>
          <div><dt className="font-medium text-[#333]">Skill</dt><dd className="mt-0.5 break-all font-mono text-[11px]">{selected.skillPath}</dd></div>
        </dl>
        <p className="mt-3">Codex uses your configured CODEX_HOME folder when set. Other agents with shell access can use the CLI directly.</p>
      </details>

      <details className="group mt-3 text-[12px] leading-5 text-[#777]">
        <summary className="flex w-fit cursor-pointer list-none items-center gap-2 font-medium text-[#555]">Command not found?<span className="transition-transform group-open:rotate-45" aria-hidden="true">+</span></summary>
        <p className="mt-3">Keep ~/.local/bin on your PATH, or call the CLI with its full path:</p>
        <code className="mt-2 block break-all rounded-md bg-white px-3 py-2 text-[11px] text-[#444]">~/.local/bin/notch-browser status --json</code>
        <p className="mt-3">If you moved or renamed the app, update the app path in the setup command.</p>
      </details>
    </div>
  );
}
