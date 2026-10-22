import Image from "next/image";
import benchmark from "./browser-benchmark-data.json";
import efficiency from "./browser-efficiency-data.json";
import power from "./browser-power-data.json";
import Reveal from "./reveal";

const publicTabs = benchmark.summary.find((result) => result.scenario === "five-public-sites");

if (!benchmark.complete || !publicTabs || !efficiency.complete || !efficiency.audit.absoluteLaunchTimesValidated || !power.complete) {
  throw new Error("The browser comparison requires a complete, verified benchmark.");
}

const memorySavedPercent = Math.round((1 - publicTabs.notch.medianMiB / publicTabs.chrome.medianMiB) * 100);

export default function BrowserComparison() {
  return (
    <section id="comparison" aria-labelledby="comparison-title" className="landing-container comparison-section">
      <Reveal>
        <p className="landing-eyebrow">Performance</p>
        <h2 id="comparison-title" className="comparison-heading">Less overhead. More headroom.</h2>
        <div className="comparison-stats">
          {/* <div className="comparison-mark" aria-hidden="true">
            <Image src="/app-icon.png" width={64} height={64} alt="" />
          </div> */}
          <dl className="comparison-stat-grid">
            <div>
              <dt>less memory than Chrome<sup>1</sup><span className="comparison-condition">Five public websites · three trials</span></dt>
              <dd>{memorySavedPercent}<span>%</span></dd>
            </div>
            <div>
              <dt>less background CPU than Chrome<sup>2</sup><span className="comparison-condition">Five hidden, idle tabs · three trials</span></dt>
              <dd>{Math.round(power.medianPairedReductionPercent)}<span>%</span></dd>
            </div>
            <div>
              <dt>less background CPU than Chrome<sup>2</sup><span className="comparison-condition">Five hidden, idle tabs · three trials</span></dt>
              <dd>~11<span>MiB</span></dd>
            </div>
          </dl>
        </div>
        <p className="comparison-positioning">Keep Chrome for the heavy lifting. Let Ink handle everything in between.</p>
        <p className="comparison-note">
          Preliminary local tests · {efficiency.machine.cpu}, {efficiency.machine.ramBytes / 1073741824} GB. Ink Debug build vs. Chrome; CPU used an isolated Chrome profile. Results vary.
        </p>
        <details className="comparison-method">
          <summary>Behind the numbers <span aria-hidden="true">+</span></summary>
          <div className="comparison-method-body">
            <ol>
              <li><strong>Memory.</strong> Five public websites in each browser, including app and helper processes. Median of three trials on {benchmark.displayDate}. Chrome {benchmark.chrome.version.replace(/^Chrome\//, "")}. <a href={benchmark.downloadPath} download>Memory measurements ↗</a></li>
              <li><strong>Background CPU.</strong> Median paired reduction versus Chrome across three preliminary five-tab background trials on {power.displayDate}. The same five websites were loaded in each browser, then kept hidden and idle for 60 seconds after a 20-second settling period. Counts each browser’s own app and helper processes. Chrome used a separate test profile; unrelated Chrome processes were excluded. Ink {power.notch.version} ({power.notch.configuration} build); Chrome {power.chrome.version}. This measures background CPU use, not active browsing or battery life. Short-lived processes between samples may be missed. <a href={power.downloadPath} download>CPU measurements ↗</a></li>
              <li><strong>App size.</strong> Installed bundles: Ink {efficiency.notchBundleMB} MB; Chrome {efficiency.chromeBundleGB.toFixed(1)} GB. Excludes website data, caches, and shared macOS frameworks, including WebKit. Measured {efficiency.displayDate}.</li>
              <li><strong>Startup.</strong> Median of five fresh launches to a fully loaded local test page, with warm system caches. Includes panel opening and automation overhead. Measured {efficiency.displayDate}. This measures Ink startup, not website loading speed.</li>
            </ol>
            <p>Preliminary local tests with Ink {efficiency.notch.version} ({efficiency.notch.configuration} build); Chrome {efficiency.chrome.version}; macOS {efficiency.machine.macOS}. <a href={efficiency.downloadPath} download>Startup and app-size measurements ↗</a></p>
          </div>
        </details>
      </Reveal>
    </section>
  );
}
