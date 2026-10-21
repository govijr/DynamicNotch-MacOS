import Image from "next/image";
import type { ReactNode } from "react";
import DemoVideo from "./demo-video";
import FeatureVideo from "./feature-video";
import BrowserComparison from "./browser-comparison";
import AgentFeatures from "./agent-features";
import Reveal from "./reveal";
import { checkoutUrl, downloadUrl } from "./product-links";
import "./landing.css";

const brands = ["Datadog", "Figma", "Ramp", "Adobe", "Stripe", "Amazon"];

function AppMark({ size = 40 }: { size?: number }) {
  return <Image src="/app-icon.png" width={size} height={size} alt="" />;
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
          <span className="text-md font-semibold">Ink</span>
        </a>
        <nav aria-label="Main navigation" className="flex shrink-0 items-center gap-5 text-base font-medium">
          <a href="#features" className="hidden transition-colors hover:text-[#777] sm:block">Features</a>
          <a href="#comparison" className="hidden transition-colors hover:text-[#777] sm:block">Compare</a>
          <a href="#agents" className="hidden transition-colors hover:text-[#777] sm:block">For agents</a>
          {/* <a href="#pricing" className="hidden transition-colors hover:text-[#777] md:block">Buy</a> */}
          <a href={downloadUrl} className="text-[13px] transition-colors hover:text-[#777] sm:text-sm">Download</a>
          <BuyLink small>Buy Ink · $5</BuyLink>
        </nav>
      </header>

      <main id="main">
        <section className="mx-auto max-w-[1120px] px-6 pb-10 pt-20 text-center sm:px-10 sm:pb-12" aria-labelledby="hero-title">
          <h1 id="hero-title" className="mx-auto max-w-[700px] text-balance text-3xl font-semibold leading-[0.98] tracking-tighter sm:text-5xl sm:leading-[0.88] lg:text-6xl">
            {/* Safari
            <span> in your notch.</span> */}
            A Browser <Image src="/safari.png" width={72} height={72} alt="" className="-mt-2 inline-block size-10 rounded-md sm:-mt-3 sm:size-12 lg:size-16" /> in
            <br/> your  macOS Notch.
          </h1>
          {/* <p className="hero-agent-description">Quick browsing for you.<br className="sm:hidden" /> A real browser for your AI agent.</p> */}
          <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
            {/* <input type="email" placeholder="Enter your email" 
            className="w-full max-w-[500px] rounded-full border border-gray-100 px-4 py-3 text-sm" /> */}
            <BuyLink>Buy Ink · $5</BuyLink>
            <a href={downloadUrl} className="inline-flex min-h-12 items-center justify-center rounded-full border border-black/15 px-6 text-[15px] font-medium transition-colors hover:bg-black/5">Download for Mac</a>
            {/* <a href="#agents" className="hero-agent-link">Explore agent features <span aria-hidden="true">↗</span></a> */}
          </div>
          <p className="mt-4 text-xs font-medium text-[#000]">One-time purchase · License required to unlock · CLI &amp; skills included</p>
          <p className="mt-2 text-xs text-[#777]">macOS 13 or later · Apple silicon &amp; Intel</p>
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

          <AgentFeatures />

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
            <a href={checkoutUrl} className="big-buy-button" aria-label="Buy Ink for Mac for $5, early discount from $19">
              <span aria-hidden="true"></span><span>Buy Ink · $5</span>
            </a>
            <a href={downloadUrl} className="mt-5 inline-flex text-sm font-medium underline underline-offset-4">Already purchased? Download for Mac</a>
          </Reveal>
        </section>

        <section id="faq" aria-labelledby="faq-title" className="faq-section">
          <div className="landing-container faq-layout">
            <h2 id="faq-title" className="faq-heading">Good to know.</h2>
            <div className="faq-questions">
              {[
                ["How do I download and activate Ink?", "Download Ink, open the disk image, and drag notch-browser into Applications. Buy a license, then copy your key from your Polar purchase email or customer portal and paste it into the app. The Mac app is currently named Notch Browser."],
                ["Already purchased?", "You can download Ink again using any Download link on this page. Your license key is in your Polar purchase email and customer portal. If you don’t see the email, check your spam folder."],
                ["How many tabs can it handle?", "There’s no fixed tab limit. Keep the tabs you need close by, though Notch Browser is designed for a focused handful of everyday tabs rather than dozens of heavy pages. How many run comfortably depends on your Mac and the sites you open."],
                ["Do I need to sign in to every site again?", "Chrome import can bring over your cookies and signed-in sessions during setup, so you don’t have to start from scratch. Some sites may still ask you to sign in again. Safari currently imports bookmarks; you’ll need to sign in to those sites again."],
                ["Can it launch at login?", "Yes. Turn on Launch at Login in the app’s menu and Notch Browser will be ready when you sign in to your Mac."],
                ["Can I embed any web app into the notch?", "Yes. Open your web app and switch to Embed mode to hide the browser controls. Your AI chat, music player, notes, or documentation can stay in the notch, just a hover away."],
                ["How is it agent native?", "The included CLI and skills let Codex, Claude Code, or another agent with shell access use your real Notch Browser tabs. Agents can read and extract page content, click, fill forms, upload chosen files, interact with embedded frames, capture screenshots, and open local HTML. Keep the app running and your Mac awake, even when the notch is collapsed."],
                ["Can I take over while an agent is browsing?", "Yes. The app shows agent activity and lets you stop control. If a site needs a CAPTCHA, sign-in verification, or camera or microphone permission, your agent can reveal the tab and hand it back to you. Complete the step, then press Resume in the app. These steps need your input."],
              ].map(([question, answer]) => (
                <details key={question} id={question === "How is it agent native?" ? "agent-faq" : undefined} className="landing-disclosure">
                  <summary>{question}<span className="disclosure-plus" aria-hidden="true">+</span></summary>
                  <p className="faq-answer">{answer}</p>
                  {question === "How is it agent native?" && (
                    <a href="#agent-setup" className="agent-skill-link">Set up your agent <span aria-hidden="true">↑</span></a>
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
            <a href={downloadUrl} className="hover:text-black">Download for Mac</a>
            <a href={checkoutUrl} className="hover:text-black">Buy a license <span aria-hidden="true">↗</span></a>
            <span>© 2026 Govi</span>
          </div>
        </div>
      </footer>
    </>
  );
}
