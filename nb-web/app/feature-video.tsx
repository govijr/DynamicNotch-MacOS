"use client";

import { useEffect, useRef, useState } from "react";

export default function FeatureVideo({ src, poster, label }: { src: string; poster: string; label: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const userPaused = useRef(false);
  const [playing, setPlaying] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    let visible = false;
    const syncPlayback = () => {
      if (visible && !document.hidden && !motion.matches && !userPaused.current) {
        void video.play().catch(() => {});
      } else {
        video.pause();
      }
    };
    const observer = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting && entry.intersectionRatio >= 0.25;
      syncPlayback();
    }, { threshold: 0.25 });
    observer.observe(video);
    motion.addEventListener("change", syncPlayback);
    document.addEventListener("visibilitychange", syncPlayback);
    return () => {
      observer.disconnect();
      motion.removeEventListener("change", syncPlayback);
      document.removeEventListener("visibilitychange", syncPlayback);
      video.pause();
    };
  }, []);

  function togglePlayback() {
    const video = videoRef.current;
    if (!video) return;
    userPaused.current = !video.paused;
    if (video.paused) {
      void video.play().catch(() => setFailed(true));
    } else {
      video.pause();
    }
  }

  return (
    <div className="relative overflow-hidden rounded-2xl sm:rounded-[20px]">
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        width={1228}
        height={720}
        className="block aspect-[307/180] w-full object-contain"
        muted
        loop
        playsInline
        preload="none"
        aria-label={label}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onError={() => setFailed(true)}
      >
        <a href={src}>Watch the demo</a>
      </video>
      {/* {failed ? (
        <a href={src} className="absolute bottom-3 right-3 rounded-full bg-white px-4 py-2 text-xs font-medium text-black shadow-sm">Open demo ↗</a>
      ) : (
        <button
          type="button"
          onClick={togglePlayback}
          aria-label={`${playing ? "Pause" : "Play"} ${label}`}
          className="absolute bottom-3 right-3 flex size-9 cursor-pointer items-center justify-center rounded-full bg-white/90 text-black shadow-sm backdrop-blur-sm transition-colors hover:bg-white sm:bottom-4 sm:right-4"
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" aria-hidden="true">
            <path d={playing ? "M2 1h3v10H2zm5 0h3v10H7z" : "m3 1 8 5-8 5z"} />
          </svg>
        </button>
      )} */}
    </div>
  );
}
