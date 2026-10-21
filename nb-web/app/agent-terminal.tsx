"use client";

import { useEffect, useRef, useState } from "react";

export function AgentSetupLink() {
  return <a href="#agent-setup" className="agent-connect-link" onClick={() => document.getElementById("agent-setup")?.setAttribute("open", "")}>Connect your agent <span aria-hidden="true">›</span></a>;
}

export default function AgentTerminal() {
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
    if (video.paused) void video.play().catch(() => setFailed(true));
    else video.pause();
  }

  return (
    <figure className="landing-container agent-showcase" aria-labelledby="agent-demo-label" aria-describedby="agent-demo-description">
      <div className="agent-native-video">
        <video ref={videoRef} src="/agentnativedemo.mp4" poster="/agentnativedemo-poster.jpg"
          width={3344} height={2160} muted loop playsInline preload="metadata"
          aria-label="Agent working in Notch Browser"
          onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)} onError={() => setFailed(true)}>
          <a href="/agentnativedemo.mp4">Watch the agent demo</a>
        </video>
        {failed ? <a href="/agentnativedemo.mp4" className="agent-video-fallback">Open demo ↗</a> : (
          <button type="button" onClick={togglePlayback} className="agent-video-control" aria-label={`${playing ? "Pause" : "Play"} agent demo`}>
            <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor" aria-hidden="true">
              <path d={playing ? "M2 1h3v10H2zm5 0h3v10H7z" : "m3 1 8 5-8 5z"} />
            </svg>
          </button>
        )}
      </div>
      <figcaption className="agent-demo-caption">
        <span id="agent-demo-label" className="agent-demo-label">Agent native</span>
        <p id="agent-demo-description">Watch an agent browse GitHub and review a pull request in Notch Browser. Your agent works in the notch, while you stay in your flow.</p>
      </figcaption>
    </figure>
  );
}
