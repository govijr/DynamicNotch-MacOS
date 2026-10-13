function ChromeIllustration() {
  return (
    <div aria-hidden="true" className="flex h-[220px] items-center justify-center px-2 sm:h-[240px] sm:px-4">
      <div className="w-full max-w-[380px] overflow-hidden rounded-xl border border-[#dedede] bg-white">
        <div className="flex h-9 items-center gap-3 border-b border-[#e9e9e9] bg-[#ececec] px-3">
          <div className="flex shrink-0 gap-1"><span className="size-1.5 rounded-full bg-[#bcbcbc]" /><span className="size-1.5 rounded-full bg-[#bcbcbc]" /><span className="size-1.5 rounded-full bg-[#bcbcbc]" /></div>
          <div className="flex min-w-0 flex-1 items-end gap-1 self-end">
            {Array.from({ length: 9 }, (_, i) => <div key={i} className={`flex h-6 min-w-0 flex-1 items-center justify-center rounded-t-md ${i === 0 ? "bg-white" : "bg-[#dfdfdf]"}`}><span className="h-1 w-3 max-w-[55%] rounded-full bg-[#bcbcbc]" /></div>)}
          </div>
        </div>
        <div className="flex h-9 items-center gap-3 border-b border-[#ededed] px-3">
          <span className="text-[12px] text-[#aaa]">‹ &nbsp; ›</span>
          <div className="flex h-5 flex-1 items-center rounded-full bg-[#f3f3f3] px-3"><span className="h-1 w-20 rounded-full bg-[#ddd]" /></div>
        </div>
        <div className="flex h-[122px] gap-4 p-4">
          <div className="w-1/5 space-y-2 border-r border-[#eee] pr-3"><div className="h-2 rounded bg-[#e7e7e7]" /><div className="h-1.5 w-4/5 rounded bg-[#eee]" /><div className="h-1.5 rounded bg-[#eee]" /><div className="h-1.5 w-3/4 rounded bg-[#eee]" /></div>
          <div className="flex-1"><div className="mb-3 h-2 w-3/5 rounded bg-[#dedede]" /><div className="mb-2 h-1.5 rounded bg-[#ededed]" /><div className="mb-4 h-1.5 w-4/5 rounded bg-[#ededed]" /><div className="grid grid-cols-3 gap-2"><div className="h-9 rounded bg-[#f2f2f2]" /><div className="h-9 rounded bg-[#f2f2f2]" /><div className="h-9 rounded bg-[#f2f2f2]" /></div></div>
        </div>
      </div>
    </div>
  );
}

function NotchIllustration() {
  return (
    <div aria-hidden="true" className="relative flex h-[220px] items-start justify-center pt-4 sm:h-[240px]">
      <div className="absolute inset-x-0 top-4 h-px bg-[#e3e3e3]" />
      <div className="notch-panel w-[76%] max-w-[270px] px-4 pb-4 pt-7 text-white">
        <div className="absolute inset-x-0 top-0 mx-auto h-3 w-20 rounded-b-lg bg-black" />
        <div className="flex gap-1 text-[9px]">
          {["Search", "AI", "X", "Docs"].map((tab, i) => <span key={tab} className={`flex h-6 min-w-0 flex-1 items-center justify-center rounded-md ${i === 0 ? "bg-white/15 text-white" : "bg-white/5 text-white/45"}`}>{tab}</span>)}
        </div>
        <div className="mt-3 flex h-7 items-center rounded-md bg-white/10 px-2.5 text-[9px] text-white/40">Search or enter a URL</div>
        <p className="mb-3 mt-6 text-center text-[15px] font-medium tracking-[-0.03em]">A quick question?</p>
        <div className="mx-auto mt-5 h-0.5 w-6 rounded-full bg-white/30" />
      </div>
    </div>
  );
}

export default function BrowserComparison() {
  return (
    <section id="comparison" aria-labelledby="comparison-title" className="mx-auto max-w-[1120px] px-6 pb-20 sm:px-10 sm:pb-28">
      <div className="mx-auto max-w-[800px] text-center">
        <h2 id="comparison-title" className="section-heading text-balance">Not every tab needs a whole browser.</h2>
        <p className="mx-auto mt-5 max-w-[660px] text-balance text-[16px] leading-[1.7] text-[#777] sm:text-[18px]">Chrome is great for the heavy lifting. But for a quick search, checking X, or keeping a few tabs handy? That&apos;s what Notch Browser is for.</p>
      </div>
      <div className="mt-9 grid gap-5 md:grid-cols-2 sm:mt-12 sm:gap-6">
        <article className="min-w-0 rounded-[28px] bg-[#f7f7f7] p-6 sm:p-8">
          <h3 className="text-[26px] font-bold tracking-[-0.045em] sm:text-[30px]">Chrome</h3>
          <p className="mt-1 text-[14px] text-[#888]">For the heavy lifting.</p>
          <ChromeIllustration />
          <p className="max-w-[390px] text-[15px] leading-[1.7] text-[#777]">Deep research, complex workflows, extensions, and dozens of tabs.</p>
        </article>
        <article className="min-w-0 rounded-[28px] border border-[#e5e5e5] bg-[#f7f7f7] p-6 sm:p-8">
          <h3 className="text-[26px] font-bold tracking-[-0.045em] sm:text-[30px]">Notch Browser</h3>
          <p className="mt-1 text-[14px] text-[#777]">For the little things.</p>
          <NotchIllustration />
          <p className="max-w-[390px] text-[15px] leading-[1.7] text-[#666]">Quick searches, AI chats, X, documentation, and your everyday tabs, just a hover away.</p>
        </article>
      </div>
      <p className="mx-auto mt-7 max-w-[660px] text-balance text-center text-[14px] leading-[1.7] text-[#777] sm:mt-8 sm:text-[15px]">Keep Chrome for the big things. Notch Browser for everything in between.</p>
    </section>
  );
}
