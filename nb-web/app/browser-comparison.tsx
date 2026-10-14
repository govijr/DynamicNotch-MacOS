import Image from "next/image";
import benchmark from "./browser-benchmark-data.json";
import Reveal from "./reveal";

const publicTabs = benchmark.summary.find((result) => result.scenario === "five-public-sites");

if (!benchmark.complete || !publicTabs) {
  throw new Error("The browser comparison requires a complete, verified benchmark.");
}

const memory = publicTabs;
const number = (value: number) => Math.round(value).toLocaleString("en-US");
const memorySavedPercent = Math.round((1 - memory.notch.medianMiB / memory.chrome.medianMiB) * 100);

export default function BrowserComparison() {
  return (
    <section id="comparison" aria-labelledby="comparison-title" className="landing-container comparison-section">
      <Reveal>
        <p className="landing-eyebrow">Memory footprint</p>
        <h2 id="comparison-title" className="comparison-heading">A lighter way to browse.</h2>
        <div className="comparison-stats">
          <div className="comparison-mark" aria-hidden="true">
            <Image src="/imagetest.png" width={64} height={64} alt="" />
          </div>
          <dl className="comparison-stat-grid">
            <div>
              <dt>Less memory than Chrome¹</dt>
              <dd>{memorySavedPercent}<span>%</span></dd>
            </div>
            <div>
              <dt>Notch Browser · 5 tabs¹</dt>
              <dd>{number(memory.notch.medianMiB)}<span>MiB</span></dd>
            </div>
            <div>
              <dt>Chrome · 5 tabs¹</dt>
              <dd>{number(memory.chrome.medianMiB)}<span>MiB</span></dd>
            </div>
          </dl>
        </div>
        <p className="comparison-positioning">Notch Browser for your everyday 4–5 tabs. Chrome for the heavy work.</p>
        <p className="comparison-note">
          ¹ Preliminary local test. App + helpers, median of 3 trials. {benchmark.machine.cpu}, {number(benchmark.machine.ramBytes / 1073741824)} GB, {benchmark.notch.configuration} build · {benchmark.displayDate}. Results vary.
          {" "}<a href={benchmark.downloadPath} download>View measurements<span aria-hidden="true"> ↗</span></a>
        </p>
      </Reveal>
    </section>
  );
}
