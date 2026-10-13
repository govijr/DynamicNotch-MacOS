"use client";

import { useEffect, useRef, useState } from "react";

export default function DemoVideo() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const shouldAutoPlay = useRef(true);
  const [isPlaying, setIsPlaying] = useState(false);
  const [hasError, setHasError] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !motion.matches && shouldAutoPlay.current) {
          void video.play().catch(() => {});
        } else {
          video.pause();
        }
      },
      { threshold: 0.2 },
    );
    const onMotionChange = () => { if (motion.matches) video.pause(); };
    motion.addEventListener("change", onMotionChange);
    observer.observe(video);
    return () => {
      observer.disconnect();
      motion.removeEventListener("change", onMotionChange);
    };
  }, []);

  function togglePlayback() {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      shouldAutoPlay.current = true;
      void video.play().catch(() => setHasError(true));
    } else {
      shouldAutoPlay.current = false;
      video.pause();
    }
  }

  return (
    <div>
      <div className="overflow-hidden rounded-xl bg-[#f5f5f5] sm:rounded-2xl">
        <video
          ref={videoRef}
          className="demo-video aspect-[82/53] w-full object-contain"
          src="/demo.mp4"
          poster="/demo-poster.png"
          muted
          loop
          playsInline
          controls
          preload="metadata"
          aria-label="Demo of Notch Browser expanding from the Mac’s notch"
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          onError={() => setHasError(true)}
        >
          Your browser does not support video. <a href="/demo.mp4">Watch the demo.</a>
        </video>
      </div>
      {/* <div className="mt-4 flex items-center justify-between gap-4 text-[13px] text-[#777]">
        <p>{hasError ? "Having trouble playing?" : "A little peek at your new browser."}</p>
        {hasError ? (
          <a href="/demo.mp4" className="font-medium text-[#111] underline underline-offset-4">Open video</a>
        ) : (
          <button onClick={togglePlayback} className="flex min-h-9 cursor-pointer items-center gap-2 font-medium text-[#111]" aria-label={isPlaying ? "Pause demo video" : "Play demo video"}>
            {isPlaying ? (
              <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="M2 1h3v10H2zm5 0h3v10H7z" /></svg>
            ) : (
              <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" aria-hidden="true"><path d="m3 1 8 5-8 5z" /></svg>
            )}
            {isPlaying ? "Pause" : "Play"}
          </button>
        )}
      </div> */}
    </div>
  );
}
