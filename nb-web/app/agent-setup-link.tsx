"use client";

export default function AgentSetupLink() {
  return (
    <a
      href="#agent-setup"
      className="mt-3 inline-flex min-h-11 items-center gap-1.5 text-[13px] text-[#06c] underline-offset-4 hover:underline"
      onClick={() => document.getElementById("agent-setup")?.setAttribute("open", "")}
    >
      Connect your agent <span className="text-xl leading-none" aria-hidden="true">›</span>
    </a>
  );
}
