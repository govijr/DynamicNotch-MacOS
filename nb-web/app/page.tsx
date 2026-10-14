import Image from "next/image";
import type { ReactNode } from "react";
import DemoVideo from "./demo-video";
import FeatureVideo from "./feature-video";
import BrowserComparison from "./browser-comparison";
import AgentSetup from "./agent-setup";
import Reveal from "./reveal";
import "./landing.css";

const checkoutUrl = "https://buy.polar.sh/polar_cl_h61CaUncTVTTbKDnENNCs7cizvFTBYopQmWaS15R88r";
const brands = ["Datadog", "Figma", "Ramp", "Adobe", "Stripe", "Amazon"];

function AppMark({ size = 40 }: { size?: number }) {
  return <Image src="/imagetest.png" width={size} height={size} alt="" className="" />;
}

function BuyLink({ children, small = false }: { children: ReactNode; small?: boolean }) {
  return (
    <a href={checkoutUrl} className={`inline-flex items-center justify-center gap-3 rounded-full bg-[#111] font-medium text-white transition-colors hover:bg-[#333] ${small ? "min-h-10 px-4 text-[14px]" : "min-h-12 px-6 text-[15px]"}`}>
      {children}
    </a>
  );
}

export default function Home() {
  return (
    <>
      <a href="#main" className="sr-only fixed left-4 top-4 z-50 rounded-md bg-black px-4 py-3 text-white focus:not-sr-only">Skip to content</a>
      <header className="mt-3 z-30 flex max-w-[800px] items-center justify-between gap-3 px-4 py-3 sm:mx-auto sm:gap-4 sm:px-7">
        <a href="#main" aria-label="Notch Browser home" className="flex shrink-0 items-center gap-2 text-[16px] font-medium tracking-[-0.035em] sm:text-[19px]">
          <AppMark size={30} />
          <span className="text-md font-semibold">Notch Browser</span>
        </a>
        <nav aria-label="Main navigation" className="flex shrink-0 items-center gap-5 text-base font-medium">
          <a href="#features" className="hidden transition-colors hover:text-[#777] sm:block">Features</a>
          <a href="#comparison" className="hidden transition-colors hover:text-[#777] sm:block">Compare</a>
          <a href="#agents" className="hidden transition-colors hover:text-[#777] sm:block">For agents</a>
          {/* <a href="#pricing" className="hidden transition-colors hover:text-[#777] md:block">Buy</a> */}
          <BuyLink small>Buy</BuyLink>
        </nav>
      </header>

      <main id="main">
        <section className="mx-auto max-w-[1120px] px-6 pb-10 pt-20 text-center sm:px-10 sm:pb-12" aria-labelledby="hero-title">
          <h1 id="hero-title" className="mx-auto max-w-[700px] text-balance text-[56px] font-semibold leading-[0.88] tracking-tighter sm:text-[80px] lg:text-6xl">
            {/* Safari
            <span> in your notch.</span> */}
            A <Image src="/safari.png" width={72} height={72} alt="" className="-mt-3 inline-block size-14 rounded-md" />
            Browser in <br/> your  macOS Notch.
          </h1>
          {/* <p className="mx-auto mt-7 max-w-[560px] text-balance text-[16px] leading-[1.7] text-[#666] sm:text-[17px]">For the quick searches, small tasks, and tabs you don’t need all day. Now your agent can use it, too.</p> */}
          <div className="mt-7 flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
            <BuyLink small>Buy</BuyLink>
            {/* <a href="#demo" className="inline-flex min-h-12 items-center gap-2 text-[14px] font-medium transition-colors hover:text-[#777]">Watch the demo<Arrow /></a> */}
          </div>
          <p className="mt-4 text-xs font-medium text-[#000]">One-time purchase · CLI & skills included</p>
        </section>

        <section id="demo" className="mx-auto max-w-[1120px] scroll-mt-24 px-6 sm:px-10" aria-label="See Notch Browser in action">
          <DemoVideo />
        </section>

        <section id="logo-garden" aria-labelledby="brands-title" className="landing-container brand-section">
          <h2 id="brands-title" className="text-center text-[13px] font-medium text-[#6e6e73]">Being used by productivity folks at</h2>
          <ul className="mt-6 grid grid-cols-3 items-center gap-x-5 gap-y-3 sm:grid-cols-6">
            {brands.map((brand) => (
              <li key={brand} className="flex h-16 min-w-0 items-center justify-center px-2">
                <Image src={`/brands/${brand.toLowerCase()}.svg`} width={140} height={60} alt={brand} className="h-10 w-full max-w-[110px] object-contain opacity-55" />
              </li>
            ))}
          </ul>
        </section>

        <section id="features" aria-labelledby="features-title" className="feature-section">
          <article className="feature-story" aria-labelledby="features-title">
            <Reveal className="landing-container feature-heading">
              <p className="landing-eyebrow">Everyday browsing</p>
              <h2 id="features-title" className="landing-heading">Just a hover away.</h2>
            </Reveal>
            <Reveal variant="media" className="landing-container feature-laptop">
              <FeatureVideo src="/demo1.mp4" poster="/demo1-poster.jpg" label="everyday browsing demo" />
            </Reveal>
          </article>

          <article className="feature-story" aria-labelledby="embed-title">
            <Reveal className="landing-container feature-heading">
              <p className="landing-eyebrow">Embed mode</p>
              <h2 id="embed-title" className="landing-heading">Your apps. A notch closer.</h2>
            </Reveal>
            <Reveal variant="media" className="landing-container feature-laptop">
              <FeatureVideo src="/demo2.mp4" poster="/demo2-poster.jpg" label="web apps in the notch demo" frame="midnight" />
            </Reveal>
          </article>
        </section>

        <BrowserComparison />

        <section id="pricing" aria-label="Buy Notch Browser" className="landing-container pricing-section">
          <Reveal>
            <p className="early-discount"><span>Early discount</span><del>$19</del></p>
            <a href={checkoutUrl} className="big-buy-button" aria-label="Buy Notch Browser for $5, early discount from $19">
              <span aria-hidden="true"></span><span>Buy for $5</span>
            </a>
          </Reveal>
        </section>

        <section id="faq" aria-labelledby="faq-title" className="faq-section">
          <div className="landing-container faq-layout">
            <h2 id="faq-title" className="faq-heading">Good to know.</h2>
            <div className="faq-questions">
              {[
                ["How many tabs can it handle?", "There’s no fixed tab limit. Keep the tabs you need close by, though Notch Browser is designed for a focused handful of everyday tabs rather than dozens of heavy pages. How many run comfortably depends on your Mac and the sites you open."],
                ["Do I need to sign in to every site again?", "Chrome import can bring over your cookies and signed-in sessions during setup, so you don’t have to start from scratch. Some sites may still ask you to sign in again. Safari currently imports bookmarks; you’ll need to sign in to those sites again."],
                ["Can it launch at login?", "Yes. Turn on Launch at Login in the app’s menu and Notch Browser will be ready when you sign in to your Mac."],
                ["Can I embed any web app into the notch?", "Yes. Open your web app and switch to Embed mode to hide the browser controls. Your AI chat, music player, notes, or documentation can stay in the notch, just a hover away."],
                ["How is it agent native?", "Notch Browser includes a command-line tool and skills for Codex and Claude Code. Your agent can open tabs, read pages, follow links, fill forms, and capture screenshots in your browser — even while the notch is collapsed. Keep the app running while your agent works."],
              ].map(([question, answer]) => (
                <details key={question} id={question === "How is it agent native?" ? "agents" : undefined} className="landing-disclosure">
                  <summary>{question}<span className="disclosure-plus" aria-hidden="true">+</span></summary>
                  <p className="faq-answer">{answer}</p>
                  {question === "How is it agent native?" && (
                    <div id="agent-setup" className="faq-agent-tools">
                      <a href="/skills/notch-browser/SKILL.md" download="SKILL.md" className="agent-skill-link">Download the agent skill <span aria-hidden="true">↗</span></a>
                      <AgentSetup />
                    </div>
                  )}
                </details>
              ))}
            </div>
          </div>
        </section>
      </main>

      <footer className="landing-footer">
        <div className="landing-container flex flex-col gap-7 py-9 md:flex-row md:items-center md:justify-between">
          <div>
            <a href="#main" className="flex items-center gap-2.5 text-[16px] font-semibold tracking-[-0.035em]"><AppMark size={30} /><span>Notch Browser</span></a>
          </div>
          <div className="flex flex-wrap items-center gap-x-5 gap-y-3 text-[13px] text-[#777]">
            <a href="#features" className="hover:text-black">Features</a>
            <a href="#agents" className="hover:text-black">For agents</a>
            <a href="#faq" className="hover:text-black">FAQ</a>
            <a href={checkoutUrl} className="hover:text-black">Get for Mac <span aria-hidden="true">↗</span></a>
            <span>© 2026 Govi</span>
          </div>
        </div>
      </footer>
    </>
  );
}
