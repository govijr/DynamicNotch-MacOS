import Image from "next/image";
import type { ReactNode } from "react";
import DemoVideo from "./demo-video";
import FeatureVideo from "./feature-video";
import BrowserComparison from "./browser-comparison";
import AgentFeatures, { AgentBenchmark } from "./agent-features";
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
        <a href="#main" aria-label="Ink home" className="flex shrink-0 items-center gap-2 text-[16px] font-medium tracking-[-0.035em] sm:text-[19px]">
          <AppMark size={30} />
          <span className="text-md font-semibold">Ink</span>
        </a>
        <nav aria-label="Main navigation" className="flex shrink-0 items-center gap-5 text-base font-medium">
          <a href="#features" className="hidden transition-colors hover:text-[#777] sm:block">Features</a>
          <a href="#comparison" className="hidden transition-colors hover:text-[#777] sm:block">Compare</a>
          <a href="#agents" className="hidden transition-colors hover:text-[#777] sm:block">For agents</a>
          <a href={downloadUrl} className="text-[13px] transition-colors hover:text-[#777] sm:text-sm">Download</a>
          <BuyLink small>Buy</BuyLink>
        </nav>
      </header>

      <main id="main">
        <section className="mx-auto max-w-[1120px] px-6 pb-10 pt-20 text-center sm:px-10 sm:pb-12" aria-labelledby="hero-title">
          <h1 id="hero-title" className="mx-auto max-w-[700px] text-balance text-3xl font-semibold leading-[0.98] tracking-tighter sm:text-5xl sm:leading-[0.88] lg:text-6xl">
            The internet.<br />One hover away.
          </h1>
          <p className="hero-agent-description">Meet Ink. Your favorite tabs and web apps, right in your Mac&apos;s notch.</p>
          <div className="mt-7 flex flex-wrap items-center justify-center gap-3">
            <BuyLink>Buy</BuyLink>
            <a href={downloadUrl} className="inline-flex min-h-12 items-center justify-center rounded-full border border-black/15 px-6 text-[15px] font-medium transition-colors hover:bg-black/5">Download for Mac</a>
          </div>
          {/* <p className="mt-4 text-xs font-medium text-[#000]">One-time purchase · License required to unlock · CLI &amp; skills included</p> */}
          <p className="mt-2 text-xs text-[#777]">macOS 13 or later · Apple silicon &amp; Intel · One-time purchase</p>
        </section>

        <section id="demo" className="mx-auto max-w-[1120px] scroll-mt-24 px-6 sm:px-10" aria-label="See Ink in action">
          <DemoVideo />
        </section>

        <section id="logo-garden" aria-labelledby="brands-title" className="landing-container brand-section">
          <h2 id="brands-title" className="text-center text-[13px] font-medium text-[#6e6e73]">Used by people at</h2>
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
              <h2 id="features-title" className="landing-heading">There when you need it. Gone when you don&apos;t.</h2>
              <p className="feature-description">Hover to browse. Click away to hide. No window juggling, no interruptions.</p>
            </Reveal>
            <Reveal variant="media" className="landing-container feature-laptop">
              <FeatureVideo src="/demo1.mp4" poster="/demo1.jpg" label="everyday browsing demo" />
            </Reveal>
          </article>

          <article id="quick-browsing" className="feature-story" aria-labelledby="quick-title">
            <Reveal className="landing-container feature-heading">
              <p className="landing-eyebrow">Quick browsing</p>
              <h2 id="quick-title" className="landing-heading">Look it up. Get back to it.</h2>
              <p className="feature-description">Docs, messages, quick searches. Everything you reach for, without switching windows.</p>
            </Reveal>
          </article>

          <article className="feature-story" aria-labelledby="embed-title">
            <Reveal className="landing-container feature-heading">
              <p className="landing-eyebrow">Embed mode</p>
              <h2 id="embed-title" className="landing-heading">Any web app. No extra windows.</h2>
              <p className="feature-description">Turn your favorite web apps into floating panels. No tabs, no toolbars, just the app.</p>
            </Reveal>
            <Reveal variant="media" className="landing-container feature-laptop">
              <FeatureVideo src="/demo2.mp4" poster="/demo2-poster.jpg" label="web apps in the notch demo" frame="midnight" />
            </Reveal>
          </article>

          <AgentFeatures />
        </section>

        <AgentBenchmark />

        <BrowserComparison />

        <section id="pricing" aria-labelledby="pricing-title" className="landing-container pricing-section">
          <Reveal>
            <h2 id="pricing-title" className="landing-heading">Less juggling. More doing.</h2>
            <p className="feature-description">Your web, always within reach. Never in your way.</p>
            <p className="early-discount"><span>Early discount · $5</span><del>$19</del></p>
            <a href={checkoutUrl} className="big-buy-button" aria-label="Buy Ink for Mac for $5, early discount from $19">
              <span aria-hidden="true"></span><span>Buy Ink for Mac</span>
            </a>
            {/* <p className="mt-4 text-xs font-medium">One-time purchase · CLI &amp; skills included</p> */}
            {/* <a href={downloadUrl} className="mt-5 inline-flex text-sm font-medium underline underline-offset-4">Already purchased? Download for Mac</a> */}
          </Reveal>
        </section>

        <section id="faq" aria-labelledby="faq-title" className="faq-section">
          <div className="landing-container faq-layout">
            <h2 id="faq-title" className="faq-heading">Good to know.</h2>
            <div className="faq-questions">
              {[
                ["How do I download and activate Ink?", "Download Ink, open the disk image, and drag notch-browser into Applications. Buy a license, then copy your key from your Polar purchase email or customer portal and paste it into the app. The Mac app is currently named Notch Browser."],
                ["Already purchased?", "You can download Ink again using any Download link on this page. Your license key is in your Polar purchase email and customer portal. If you don’t see the email, check your spam folder."],
                ["How many tabs can it handle?", "There’s no fixed limit. Ink is designed for a handful of everyday tabs; capacity depends on your Mac and the sites you open."],
                ["Do I need to sign in to every site again?", "Chrome import can bring over cookies and signed-in sessions. Some sites may ask you to sign in again. Safari imports bookmarks only, so you’ll need to sign in to those sites again."],
                ["Can it launch at login?", "Yes. Turn on Launch at Login in the app’s menu and Ink will be ready when you sign in."],
                ["Can I embed any web app into the notch?", "Open your web app and switch to Embed mode to hide the browser controls."],
                ["How is it agent native?", "Ink lets local coding agents browse your tabs and use your existing logins. Connect during onboarding, then keep Ink running and your Mac awake while your agent works."],
                ["Can I take over while an agent is browsing?", "Yes. Stop agent control whenever you need to. For sign-in checks, CAPTCHAs, or camera and microphone permissions, complete the step yourself, then press Resume."],
              ].map(([question, answer]) => (
                <details key={question} id={question === "How is it agent native?" ? "agent-faq" : undefined} className="landing-disclosure">
                  <summary>{question}<span className="disclosure-plus" aria-hidden="true">+</span></summary>
                  <p className="faq-answer">{answer}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        
      </main>

      <footer className="landing-footer">
        <div className="landing-container flex flex-col gap-7 py-9 md:flex-row md:items-center md:justify-between">
          <div>
            <a href="#main" className="flex items-center gap-2.5 text-[16px] font-semibold tracking-[-0.035em]"><AppMark size={30} /><span>Ink</span></a>
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
