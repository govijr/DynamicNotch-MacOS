"use client";

import { useState } from "react";

export default function WhyNotFree() {
  const [showGif, setShowGif] = useState(false);

  return (
    <div className="group relative z-40 mt-7 inline-flex">
      <button
        type="button"
        className="cursor-help text-base font-medium tracking-tighter underline"
        aria-describedby="why-not-free-tooltip"
      >
        Why not free?
      </button>
      <div
        id="why-not-free-tooltip"
        role="tooltip"
        className="pointer-events-none invisible absolute top-full left-1/2 z-40 mt-3 w-[260px] -translate-x-1/2 rounded-2xl bg-black p-3 text-left text-white opacity-0 shadow-lg transition-opacity group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100"
      >
        {/* Drop the gif at nb-web/public/why-not-free.gif */}
        <img
          src="/broke.gif"
          alt=""
          className={`mb-2.5 h-auto w-full rounded-xl bg-[#222] ${showGif ? "" : "hidden"}`}
          onLoad={() => setShowGif(true)}
        />
        <p className="px-1 text-[13px] font-medium leading-snug tracking-tight">
          i got laid from my job and you want me to give things for free??
        </p>
      </div>
    </div>
  );
}
