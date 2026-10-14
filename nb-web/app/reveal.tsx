"use client";

import { useEffect, useRef, type ReactNode } from "react";

export default function Reveal({
  children,
  className = "",
  variant = "rise",
}: {
  children: ReactNode;
  className?: string;
  variant?: "rise" | "media" | "fade";
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element || !("IntersectionObserver" in window)) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (motion.matches || element.getBoundingClientRect().top < window.innerHeight) return;

    const reveal = () => {
      element.dataset.reveal = "visible";
      observer.disconnect();
    };
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) reveal();
    }, { rootMargin: "0px 0px -24px 0px", threshold: 0 });

    // Server-rendered content stays visible until an observer can reveal it.
    element.dataset.reveal = "pending";
    observer.observe(element);
    const onMotionChange = () => { if (motion.matches) reveal(); };
    motion.addEventListener("change", onMotionChange);
    return () => {
      observer.disconnect();
      motion.removeEventListener("change", onMotionChange);
      delete element.dataset.reveal;
    };
  }, []);

  return (
    <div ref={ref} className={`landing-reveal ${className}`} data-reveal-variant={variant}
      onFocusCapture={() => { if (ref.current) ref.current.dataset.reveal = "visible"; }}>
      {children}
    </div>
  );
}
